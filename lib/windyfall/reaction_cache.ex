defmodule Windyfall.ReactionCache do
  use GenServer
  import Ecto.Query, warn: false

  alias Windyfall.Repo
  alias Windyfall.Messages.Reaction
  alias Windyfall.Messages
  alias WindyfallWeb.Presence

  @max_size 10000000
  @lru_ttl 300_000

  # Client API
  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  def get(mid, emoji), do: GenServer.call(__MODULE__, {:get, mid, emoji})
  def toggle(mid, uid, emoji), do: GenServer.cast(__MODULE__, {:toggle, mid, uid, emoji})
  @doc """
  Ensures that data for the given message IDs is loaded into the cache if not present.
  """
  def ensure_cached(message_ids) when is_list(message_ids) do
    GenServer.cast(__MODULE__, {:ensure_cached, message_ids})
  end
  def ensure_cached(_), do: :ok

  # Server
  def init(_) do
    Process.send_after(self(), :prune, @lru_ttl)
    {:ok, %{counts: %{}, users: %{}, lru: []}}
  end

  def handle_cast({:ensure_cached, message_ids}, state) do
    # 1. Identify message IDs not currently in the cache (counts map is a good proxy)
    ids_to_load = Enum.filter(message_ids, fn mid -> !Map.has_key?(state.counts, mid) end)

    new_state =
      if ids_to_load != [] do
        # 2. Fetch all reactions for the missing IDs in ONE batch query
        batch_reaction_data = Messages.get_reactions_for_message_batch(ids_to_load)
        # batch_reaction_data is a list like: [{mid1, e1, u1}, {mid1, e2, u2}, {mid2, e1, u3}, ...]

        # 3. Process the batch data to build updates for counts and users maps
        {counts_updates, users_updates} =
          Enum.reduce(batch_reaction_data, {%{}, %{}}, fn {mid, emoji, uid}, {c_acc, u_acc} ->
            # Accumulate counts per message_id -> emoji
            new_c_acc = Map.update(c_acc, mid, %{emoji => 1}, fn mid_counts ->
              Map.update(mid_counts, emoji, 1, & &1 + 1)
            end)

            # Accumulate users per message_id -> user_id -> MapSet<emoji>
            new_u_acc = Map.update(u_acc, mid, %{uid => MapSet.new([emoji])}, fn mid_users ->
              Map.update(mid_users, uid, MapSet.new([emoji]), &MapSet.put(&1, emoji))
            end)

            {new_c_acc, new_u_acc}
          end)
          # counts_updates is like %{mid1 => %{e1 => count, e2 => count}, mid2 => %{...}}
          # users_updates is like %{mid1 => %{u1 => MapSet<e1>, u2 => MapSet<e2>}, mid2 => %{...}}


        # 4. Merge the updates into the existing state
        # For any `mid` in updates, its counts/users maps completely replace any old (though unlikely) entries
        final_counts = Map.merge(state.counts, counts_updates)
        final_users = Map.merge(state.users, users_updates)

        # 5. Update LRU for all the IDs that were loaded
        final_lru = Enum.reduce(ids_to_load, state.lru, fn mid, lru_acc ->
           update_lru(mid, lru_acc)
        end)

        # Return the fully updated state
        %{state | counts: final_counts, users: final_users, lru: final_lru}

      else
        # No IDs needed loading, return original state
        state
      end

    {:noreply, new_state}
  end

  def handle_call({:get, mid, emoji}, _from, state) do
    # --- Modify get to potentially load users map too ---
    %{counts: counts, users: users, lru: lru} = state
    {count, new_state} = case Map.get(counts, mid) do
      nil ->
        # No need to check active?(mid) here, toggle/get implies interest
        # Load counts AND users map
        {db_counts, db_users} = load_from_db(mid)
        new_counts = Map.put(counts, mid, db_counts)
        new_users = Map.put(users, mid, db_users) # <-- Store the loaded users map
        new_lru = update_lru(mid, lru)
        # Return count and the updated state including the users map
        {Map.get(db_counts, emoji, 0), %{state | counts: new_counts, users: new_users, lru: new_lru}}

      cached_counts ->
        new_lru = update_lru(mid, lru)
        {Map.get(cached_counts, emoji, 0), %{state | lru: new_lru}}
    end
    {:reply, count, new_state}
  end

  def handle_cast({:toggle, mid, uid, emoji}, state) do
    # 1. Ensure data for the message is loaded before toggling
    state = ensure_message_loaded_for_toggle(state, mid)

    # 2. Proceed with toggle logic
    %{counts: counts, users: users, lru: lru} = state

    # Initialize message entries if missing (put_new ensures existing are kept)
    counts = Map.put_new(counts, mid, %{})
    users = Map.put_new(users, mid, %{})

    # Use get_in for safe access, default to empty set if user hasn't reacted to this message yet
    user_emojis_set = get_in(users, [mid, uid]) || MapSet.new()

    {new_counts, new_users} =
      if MapSet.member?(user_emojis_set, emoji) do
        # --- REMOVE existing reaction ---
        current_emoji_count = get_in(counts, [mid, emoji]) || 1 # Default to 1 if somehow missing but user has it
        new_emoji_count = max(current_emoji_count - 1, 0)

        # Update counts map: Remove emoji key if count drops to 0
        temp_counts =
          if new_emoji_count == 0 do
            update_in(counts, [mid], &Map.delete(&1, emoji))
          else
            put_in(counts, [mid, emoji], new_emoji_count)
          end

        # Update users map: Remove emoji from user's set
        updated_user_emojis_set = MapSet.delete(user_emojis_set, emoji)

        # *** START: Edge Case Handling ***
        # If the user's emoji set is now empty, remove the user ID entry for this message.
        temp_users =
          if MapSet.size(updated_user_emojis_set) == 0 do
             # Remove the uid key from the users[mid] map
             update_in(users, [mid], &Map.delete(&1, uid))
          else
             # Otherwise, just update the user's emoji set
             put_in(users, [mid, uid], updated_user_emojis_set)
          end
        # *** END: Edge Case Handling ***

        {temp_counts, temp_users}

      else
        # --- ADD new reaction ---
        new_emoji_count = (get_in(counts, [mid, emoji]) || 0) + 1
        updated_user_emojis_set = MapSet.put(user_emojis_set, emoji)

        {
          put_in(counts, [mid, emoji], new_emoji_count),
          put_in(users, [mid, uid], updated_user_emojis_set)
        }
      end

    # --- Optional Cleanup: Remove empty message entries ---
    # If a message ends up with no reactions at all, remove its key
    final_counts = if Map.get(new_counts, mid) == %{},
      do: Map.delete(new_counts, mid),
      else: new_counts

    # If a message ends up with no users reacting at all, remove its key
    final_users = if Map.get(new_users, mid) == %{},
      do: Map.delete(new_users, mid),
      else: new_users

    # Determine action for persistence
    reacted = is_reacted?(final_users, mid, uid, emoji)

    # Async persistence
    Task.start(fn -> persist_reaction(mid, uid, emoji, reacted) end)

    # Broadcast the change
    current_count_for_emoji = get_in(final_counts, [mid, emoji]) || 0
    broadcast_payload = 
      if current_count_for_emoji > 0 do
        # Find all users who reacted with this specific emoji on this message
        users_who_reacted = 
          (get_in(new_users, [mid]) || %{}) # Get {uid => MapSet<emoji>} for this message
          |> Enum.filter(fn {_user_id, emojis_set} -> MapSet.member?(emojis_set, emoji) end)
          |> Enum.map(fn {user_id, _emojis_set} -> user_id end)
          |> MapSet.new()

        # Construct the reaction map matching the structure in ChatLive
        updated_reaction_map = %{
          emoji: emoji, 
          count: current_count_for_emoji, 
          users: users_who_reacted, 
          message_id: mid 
          # Add other fields like 'id' if needed by components, though maybe not essential here
        }
        {:reaction_updated, mid, updated_reaction_map}
      else
        # Reaction count is zero, broadcast removal
        {:reaction_removed, mid, %{emoji: emoji, message_id: mid}} # Send minimal info
      end
    Phoenix.PubSub.broadcast!(Windyfall.PubSub, Windyfall.PubSubTopics.reactions(mid), broadcast_payload)

    # Return updated state
    {:noreply, %{
      state |
      counts: new_counts, # The result after toggling
      users: new_users,   # The result after toggling
      lru: update_lru(mid, lru) # Update LRU for the toggled message
    }}
  end

  def handle_info(:prune, state) do
    Process.send_after(self(), :prune, @lru_ttl)
    active_ids = Presence.list_active_message_ids()
    
    new_state = state
    |> prune_inactive(active_ids)
    |> enforce_lru_limit()

    {:noreply, new_state}
  end

  defp ensure_message_loaded_for_toggle(state, mid) do
    if Map.has_key?(state.counts, mid) do
      state # Already loaded
    else
      # Load from DB. No need to check active? here, toggle implies interest.
      {db_counts, db_users} = load_from_db(mid)
      %{state |
        counts: Map.put(state.counts, mid, db_counts),
        users: Map.put(state.users, mid, db_users),
        lru: update_lru(mid, state.lru)
      }
    end
  end

  defp is_reacted?(users, mid, uid, emoji) do
    # Use get_in with default to safely retrieve the potential set
    potential_set = get_in(users, [mid, uid])

    # Perform the type check and membership check in the function body
    case potential_set do
      emoji_set when is_struct(emoji_set, MapSet) -> # Check if it's specifically a MapSet struct
        MapSet.member?(emoji_set, emoji)
      _ -> # Handles nil or any other unexpected type
        false
    end
  end

  defp active?(mid), do: mid in Presence.list_active_message_ids()

  defp load_from_db(mid) do
    reactions = Repo.all(
      from r in Reaction,
        where: r.message_id == ^mid,
        select: {r.emoji, r.user_id} # Select only needed fields
    )

    # Build counts map AND user map from individual reactions
    Enum.reduce(reactions, {%{}, %{}}, fn {emoji, uid}, {count_acc, user_acc} ->
      # Accumulate counts per emoji
      new_count_acc = Map.update(count_acc, emoji, 1, & &1 + 1)

      # Accumulate users per user_id -> MapSet<emoji>
      # Ensure user_acc[uid] is initialized as a MapSet before adding the emoji
      new_user_acc = update_in(user_acc, [uid], fn existing_set ->
         MapSet.put(existing_set || MapSet.new(), emoji)
      end)

      {new_count_acc, new_user_acc} # Return tuple of both maps
    end)
  end

  defp persist_reaction(mid, uid, emoji, reacted) do
    if reacted do
      Repo.insert!(%Reaction{message_id: mid, user_id: uid, emoji: emoji})
    else
      Repo.delete_all(
        from r in Reaction,
        where: r.message_id == ^mid and r.user_id == ^uid and r.emoji == ^emoji
      )
    end
  end

  defp prune_inactive(%{counts: counts, users: users, lru: lru} = state, active_ids) do
    {new_counts, new_users, new_lru} = Enum.reduce(lru, {counts, users, []}, fn mid, {c_acc, u_acc, l_acc} ->
      if mid in active_ids do
        {c_acc, u_acc, [mid | l_acc]}
      else
        {Map.delete(c_acc, mid), Map.delete(u_acc, mid), l_acc}
      end
    end)
    
    %{state | counts: new_counts, users: new_users, lru: new_lru}
  end

  defp enforce_lru_limit(%{counts: counts, lru: lru} = state) do
    if map_size(counts) > @max_size do
      [oldest | rest] = Enum.reverse(lru)
      %{state | counts: Map.delete(counts, oldest), lru: rest}
    else
      state
    end
  end

  defp update_lru(mid, lru), do: [mid | Enum.reject(lru, &(&1 == mid))] |> Enum.take(@max_size * 2)
end
