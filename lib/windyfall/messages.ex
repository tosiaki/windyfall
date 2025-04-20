defmodule Windyfall.Messages do
  @moduledoc """
  The Messages context.
  """

  import Ecto.Query, warn: false
  alias Windyfall.Repo

  alias Windyfall.Messages.{Message, Thread, Topic}
  alias Windyfall.Accounts.User
  alias WindyfallWeb.CoreComponents
  alias Windyfall.Messages.Reaction
  alias Windyfall.Messages.Share
  alias Windyfall.Messages.Topic
  alias Windyfall.Messages.Bookmark
  alias Windyfall.Messages.Attachment
  alias Windyfall.PubSubTopics
  alias WindyfallWeb.Endpoint

  use WindyfallWeb, :verified_routes

  @page_size 50

  @doc """
  Lists all threads by topic path
  """
  def list_threads(filter) do
    default_avatar = WindyfallWeb.CoreComponents.default_avatar_path()

    base_query = from t in Thread,
      # Use left_join for user in case a thread somehow loses its user link
      left_join: u in assoc(t, :creator),
      # Use inner_join for messages to ensure only threads with messages appear (or left_join if empty threads are okay)
      # Let's assume inner_join is desired based on previous queries using count(m.id) > 0 implicitly
      inner_join: m in Message, on: m.thread_id == t.id,
      group_by: [t.id, u.id], # Group by thread and user
      order_by: [desc: max(m.inserted_at)],
      select: %{
        id: t.id,
        title: t.title,
        message_count: count(m.id),
        last_message_at: max(m.inserted_at),
        first_message_at: min(m.inserted_at),
        user_id: t.user_id, # ID of the thread creator
        author_name: coalesce(u.display_name, "Anonymous"),
        author_avatar: coalesce(u.profile_image, ^default_avatar), # Use helper
        user_handle: coalesce(u.handle, fragment("? || ?", "user-", t.user_id)),
        first_message_preview:
          fragment("""
          SUBSTRING(
            (ARRAY_AGG(? ORDER BY ? ASC) FILTER (WHERE ? IS NOT NULL))[1]
            FROM 1 FOR 280
          )
          """, m.message, m.inserted_at, m.message)
        # Add topic_id or topic_path if needed directly in the list view often
        # topic_path: select topic path if joining topics
      }

    # Apply filter dynamically
    query =
      case filter do
        {:topic_id, topic_id} ->
          # Need to join Topic table to filter by it
          base_query
          |> join(:inner, [t], topic in assoc(t, :topic), on: topic.id == ^topic_id)
          # You might want to select topic.path here too if needed in the list

        {:user_id, user_id} ->
          # Filter directly on threads.user_id (thread creator)
          # NOTE: This differs from the original :user_handle query which filtered by t.user_id.
          # If you need threads *associated* with a user (not just created by), adjust the schema/query.
          # Assuming the goal is threads *created* by the user:
          where(base_query, [t], t.user_id == ^user_id)

        # Add :global case if you ever need to list *all* threads
        # :global -> base_query

        _ ->
          # Return an empty query or raise error for invalid filter
          from(t in Thread, where: false, select: %{}) # Empty query
      end

    Repo.all(query)
    # Post-process if needed (like the handle fallback, though done in SQL now)
    # |> Enum.map(fn thread ->
    #   Map.put(thread, :author_avatar, CoreComponents.user_avatar(thread.author_avatar)) # Ensure correct path
    # end)
  end

  @doc """
  Lists items (threads or shares) for a given context filter.
  Returns a list of maps, each with a `:type` (:thread or :share) and `:item` data.
  Sorted by relevant activity time.
  """
  def list_context_items(filter) do
    # Fetch threads directly belonging to the context (originals AND spin-offs created here)
    direct_threads = list_threads_for_context(filter)

    # Fetch shares of OTHER threads targeted at this context
    shared_items = list_shared_items_for_context(filter) # Keep this as is

    # Map direct threads
    mapped_direct_threads = Enum.map(direct_threads, fn thread_map ->
       %{
         type: :thread, # Mark as type thread
         item: thread_map, # The map containing thread details
         sort_key: thread_map.last_message_at || thread_map.inserted_at # Use last activity or creation time
       }
    end)

    # Map shares
    mapped_shared_items = Enum.map(shared_items, fn share_record ->
       %{
         type: :share, # Mark as type share
         item: share_record, # The Share struct with preloads
         sort_key: share_record.inserted_at # Sort shares by when they were shared
       }
    end)

    # Combine and sort
    all_items = (mapped_direct_threads ++ mapped_shared_items)
      |> Enum.sort_by(& &1.sort_key, {:desc, NaiveDateTime})

    all_items
  end

  # Helper to get threads for the context
  defp list_threads_for_context(filter) do
    default_avatar = WindyfallWeb.CoreComponents.default_avatar_path()

    # Base query selects all threads matching the context
    base_query = from t in Thread,
      # JOIN ON CREATOR (for author info)
      join: c in assoc(t, :creator),
      # LEFT JOIN needed if a thread could theoretically have 0 messages (e.g., error during creation)
      # If threads ALWAYS have at least the first message, INNER JOIN is fine. Let's use LEFT for safety.
      left_join: m in Message, on: m.thread_id == t.id,
      group_by: [t.id, c.id], # Group by thread and creator
      order_by: [desc: max(m.inserted_at)], # Order by latest activity within the thread
      select: %{
        id: t.id,
        title: t.title,
        message_count: count(m.id),
        last_message_at: max(m.inserted_at),
        # first_message_at removed
        inserted_at: t.inserted_at, # Thread creation time
        creator_id: t.creator_id,
        author_name: coalesce(c.display_name, "Anonymous"),
        author_avatar: coalesce(c.profile_image, ^default_avatar),
        user_handle: c.handle, # Creator's handle
        topic_id: t.topic_id, # Context topic ID (if any)
        user_id: t.user_id,   # Context user ID (if any)
        # --- Important: Select spin_off_of_message_id ---
        spin_off_of_message_id: t.spin_off_of_message_id,
        # --- Generate preview ---
        first_message_preview: fragment("""
          SUBSTRING( (ARRAY_AGG(? ORDER BY ? ASC) FILTER (WHERE ? IS NOT NULL))[1] FROM 1 FOR 280 )
          """, m.message, m.inserted_at, m.message)
      }

    # Apply context filter
    query =
      case filter do
        {:topic_id, topic_id} -> where(base_query, [t], t.topic_id == ^topic_id)
        {:user_id, user_id} -> where(base_query, [t], t.user_id == ^user_id)
        # Add other filters if needed (e.g., global)
        _ -> from(t in Thread, where: false, select: %{}) # Empty for invalid filter
      end

    Repo.all(query)
  end

  # Helper to get shares targeted at the context
  defp list_shared_items_for_context(filter) do
    # Query to get just the first message of a thread
    first_message_query = from(m in Message, order_by: [asc: m.inserted_at], limit: 1)

    base_query = from s in Share,
                preload: [:user], # Sharer
                # Preload thread, its creator/context, AND its first message
                preload: [thread: [:creator, :user, :topic, messages: ^first_message_query]]

    query =
      case filter do
        {:topic_id, topic_id} -> where(base_query, [s], s.target_topic_id == ^topic_id)
        {:user_id, user_id} -> where(base_query, [s], s.target_user_id == ^user_id)
        _ -> from(s in Share, where: false)
      end

    Repo.all(query |> order_by(desc: :inserted_at))
  end

  defp enhance_threads_with_metadata(threads) do
    thread_ids = Enum.map(threads, & &1.id)

    first_messages = Repo.all(
      from m in Message,
        where: m.thread_id in ^thread_ids,
        distinct: m.thread_id,
        order_by: [m.thread_id, asc: :inserted_at],
        preload: [:user]
    )

    message_map = Enum.group_by(first_messages, & &1.thread_id)

    Enum.map(threads, fn thread ->
      first_message = message_map |> Map.get(thread.id, []) |> List.first()
      
      %{
        id: thread.id,
        title: thread.title,
        message_count: thread.message_count,
        last_message_at: thread.last_message_at,
        first_message_preview: get_first_message_preview(first_message, thread),
        author_avatar: get_author_avatar(first_message, thread),
        author_name: get_author_name(first_message, thread)
      }
    end)
  end

  defp get_first_message_preview(nil, thread), do: "New thread: #{thread.title}"
  defp get_first_message_preview(message, _thread), do: truncate(message.message, 100)

  defp get_author_avatar(nil, thread) do
    if thread.user, do: thread.user.profile_image, else: "/images/default-avatar.png"
  end
  defp get_author_avatar(message, _thread), do: message.user.profile_image

  defp get_author_name(nil, thread) do
    if thread.user, do: thread.user.display_name, else: "Anonymous"
  end
  defp get_author_name(message, _thread), do: message.user.display_name

  defp truncate(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0..max_length) <> "..."
    else
      text
    end
  end

  @doc """
  Creates a new thread
  """
  def create_thread(title, %{topic_id: topic_id}, user) do
    Repo.transaction(fn ->
      thread = Repo.insert!(%Thread{title: title, topic_id: topic_id})
      create_message(title, thread.id, user)
      thread
    end)
  end

  def create_thread(title, %{user_handle: user_handle}, user) do
    Repo.transaction(fn ->
      thread = Repo.insert!(%Thread{title: title, creator_id: user.id})
      create_message(title, thread.id, user)
      thread
    end)
  end

  def create_thread_with_message(title, message, type, identifier, user) do
    effective_title = generate_effective_title(title, message)

    Repo.transaction(fn ->
      # Start changeset, always set the creator
      thread_changeset =
        %Thread{}
        |> Thread.changeset(
          %{title: effective_title, creator_id: user.id},
          type,
          identifier
        ) # Set creator_id

      # Attempt to insert the thread
      case Repo.insert(thread_changeset) do
        {:ok, thread} ->
          # Now create the first message using the *actual* thread.id and creator user
          case create_message(message, thread.id, user) do
            {:ok, first_message} ->
              # Update the thread counts AFTER the first message is created
              updated_thread = update_thread_counts(thread, first_message)
              IO.inspect updated_thread, label: "updated_thread after create message"
              # Fetch preloads if necessary (e.g., creator for broadcast)
              # Example: Repo.preload(updated_thread, [:creator, :topic, :user])
              {:ok, updated_thread} # Return the updated thread

            {:error, message_changeset} ->
              Repo.rollback({:changeset, message_changeset}) # Rollback if message creation fails
          end

        {:error, thread_changeset} ->
          Repo.rollback({:changeset, thread_changeset}) # Rollback if thread creation fails
      end
    end)
  end

  # Helper to generate title if needed
  defp generate_effective_title(title, message) do
    cond do
      # Title provided and not blank
      title && String.trim(title) != "" ->
        String.trim(title) |> WindyfallWeb.TextHelpers.truncate(80) # Max length for titles

      # No title, but message exists
      message && String.trim(message) != "" ->
        message
        |> String.trim()
        |> String.split() # Split into words
        |> Enum.take(8) # Take first ~8 words
        |> Enum.join(" ")
        |> WindyfallWeb.TextHelpers.truncate(80) # Truncate if needed

      # Fallback if both are blank
      true ->
        "Thread started #{DateTimeHelpers.format_datetime(NaiveDateTime.utc_now())}"
    end
  end

  # Update thread counts - should be called AFTER first message exists
  # Takes the created Thread struct and the first Message struct
  defp update_thread_counts(thread, first_message) do
     Ecto.Changeset.change(thread, %{
       message_count: 1,
       last_message_at: first_message.inserted_at
     })
     |> Repo.update!() # Use update! as we expect thread to exist
  end

  defp list_messages_query do
    from p in Message,
      left_join: u in assoc(p, :user),
      select: %{id: p.id, message: p.message, display_name: u.display_name, profile_image: u.profile_image, user_id: u.id},
      limit: 50,
      order_by: [desc: :id]
  end

  @doc """
  Lists all messages in thread
  """
  def list_messages(nil), do: []
  def list_messages(thread_id) do
    Message
    |> where([m], m.thread_id == ^thread_id)
    |> order_by([m], asc: m.inserted_at)
    |> preload([:user, :reactions])
    |> Repo.all()
    |> Enum.map(&process_message/1)
  end


  defp process_message(msg) do
    user = msg.user || %{
      id: nil,
      display_name: "Anonymous",  # Add default value
      profile_image: "/images/default-avatar.png"
    }

    %{
      id: msg.id,
      message: msg.message,
      inserted_at: msg.inserted_at,
      user: %{
        id: user.id,
        display_name: user.display_name || "Anonymous",
        profile_image: user.profile_image || "/images/default-avatar.png"
      },
      reactions: process_reactions(msg.id, msg.reactions || [])
    }
  end

  def process_reactions(message_id, nil), do: []
  def process_reactions(message_id, reactions) do
    reactions
    |> Enum.group_by(& &1.emoji)
    |> Enum.map(fn {emoji, entries} ->
      %{
        id: "reaction_#{message_id}_#{emoji}",
        emoji: emoji,
        count: length(entries),
        users: MapSet.new(Enum.map(entries, & &1.user_id)),
        message_id: message_id,
        animation: "none"
      }
    end)
  end

  def process_message2(msg) do
    %{
      id: msg.id,
      content: msg.message,
      inserted_at: msg.inserted_at,
      user_id: msg.user.id,
      display_name: msg.user.display_name,
      profile_image: msg.user.profile_image
    }
  end

  def process_reactions2(messages) do
    Enum.flat_map(messages, fn msg ->
      (msg.reactions || [])
      |> Enum.group_by(& &1.emoji)
      |> Enum.map(fn {emoji, reactions} ->
        %{
          id: "reaction_#{msg.id}_#{emoji}",
          emoji: emoji,
          count: length(reactions),
          message_id: msg.id,
          users: Enum.map(reactions, & &1.user_id)
        }
      end)
    end)
  end

  def get_messages_before_id(thread_id, oldest_visible_id \\ nil) do
    query_base = from(m in Message,
        where: m.thread_id == ^thread_id,
        order_by: [desc: m.id], # Use ID for stable pagination
        limit: 50,
        # --- Preload user AND the message being replied to (replying_to) ---
        # --- Also preload the user of the message being replied to ---
        preload: [
          :user,
          :attachments,
          reactions: [:user], # Preload reactions and their users
          replying_to: [:user] # Preload parent message and its user
        ]
      )

    query =
      # If oldest_visible_id is provided, add the WHERE clause
      if oldest_visible_id do
        where(query_base, [m], m.id < ^oldest_visible_id)
      else
        # Initial load (oldest_visible_id is nil), no WHERE clause needed
        query_base
      end

    messages = Repo.all(query) |> Enum.reverse() # Reverse to get asc order

    # Determine if we are at the beginning by checking if fewer messages than limit were returned
    # We check *before* potentially removing messages if oldest_visible_id is nil
    loaded_count = length(messages)
    at_beginning = loaded_count < 50

    at_beginning = length(messages) < 50
    {messages, at_beginning}
  end

  @doc """
  Fetches a batch of messages centered around a target message ID within a thread.
  Returns {messages, at_beginning, at_end}, where messages are sorted chronologically.
  """
  def messages_around(thread_id, target_message_id, limit_before \\ @page_size / 2, limit_after \\ @page_size / 2) when is_integer(thread_id) and is_integer(target_message_id) do
    limit_before = trunc(limit_before)
    limit_after = trunc(limit_after) # Includes the target message itself

    # Query for messages BEFORE the target (inclusive option might be simpler)
    # Let's fetch target + messages AFTER first
    query_after =
      from m in Message,
      where: m.thread_id == ^thread_id and m.id >= ^target_message_id,
      order_by: [asc: m.id],
      limit: ^limit_after + 1, # +1 to check if we are at the end
      preload: [:user, :attachments, reactions: [:user], replying_to: [:user]]

    messages_after_target = Repo.all(query_after)
    at_end = length(messages_after_target) <= limit_after
    messages_after_target = Enum.take(messages_after_target, limit_after) # Take only the limit

    # Query for messages BEFORE the target
    query_before =
      from m in Message,
      where: m.thread_id == ^thread_id and m.id < ^target_message_id,
      order_by: [desc: m.id], # Fetch descending from target
      limit: ^limit_before + 1, # +1 to check if we are at the beginning
      preload: [:user, :attachments, reactions: [:user], replying_to: [:user]]

    messages_before_target = Repo.all(query_before) |> Enum.reverse() # Reverse to get chronological
    at_beginning = length(messages_before_target) <= limit_before
    messages_before_target = Enum.take(messages_before_target, limit_before) # Take only the limit

    # Combine and ensure target is included if found
    combined_messages = messages_before_target ++ messages_after_target |> Enum.uniq_by(& &1.id)

    # Recalculate at_beginning/at_end based on actual combined results vs limits *after* fetching
    # This logic might need refinement depending on exact desired edge case behavior.
    # Example: if target is the very first message, query_before will be empty.
    # If target is very last, query_after might only return the target.

    # Basic check based on limits for now:
    actual_before_count = Enum.count(combined_messages, &(&1.id < target_message_id))
    actual_after_count = Enum.count(combined_messages, &(&1.id > target_message_id))

    final_at_beginning = actual_before_count < limit_before # Simplified check
    final_at_end = actual_after_count < limit_after     # Simplified check


    {combined_messages, final_at_beginning, final_at_end}
  end

  defp get_user_id_from_msg(%{user: %User{id: id}}) when not is_nil(id), do: id
  defp get_user_id_from_msg(%{user: %{id: id}}) when not is_nil(id), do: id # Handle map case too
  defp get_user_id_from_msg(%{user_id: id}) when not is_nil(id), do: id
  defp get_user_id_from_msg(_), do: nil # Return nil if no user ID found

  @spec group_messages([map()]) :: [map()]
  def group_messages(messages) do
    messages
    |> Enum.sort_by(& &1.inserted_at, {:asc, NaiveDateTime}) # Ensure sorting happens first
    |> Enum.chunk_while(
         [],
         fn msg, acc ->
           # The 'acc' is the growing list for the current chunk, newest messages are at the head.
           # We need to compare 'msg' with the *last* message added to the chunk (head of acc).
           if can_group?(msg, List.first(acc)), # Pass only the previous message for comparison
             do: {:cont, [msg | acc]}, # Add msg to the current chunk accumulator
             else: {:cont, Enum.reverse(acc), [msg]} # Finish the current chunk, start a new one with msg
         end,
         fn
           [] -> {:cont, []} # Handle case where input is empty
           acc -> {:cont, Enum.reverse(acc), []} # Process the final accumulator
         end
       )
    |> Enum.reject(&Enum.empty?/1) # Remove any potentially empty groups
    |> Enum.map(&format_group/1)   # Format each valid group
  end

  defp create_group(msg) do
    %{
      user_id: msg.user_id,
      display_name: msg.display_name,
      profile_image: msg.profile_image,
      messages: [msg],
      first_inserted: msg.inserted_at,
      last_inserted: msg.inserted_at
    }
  end

  defp sort_messages(messages) do
    Enum.sort_by(messages, & &1.inserted_at, {:asc, NaiveDateTime})
  end

  @spec sanitize_messages([map()]) :: [map()]
  defp sanitize_messages(messages) do
    Enum.map(messages, fn msg ->
      user = msg.user || %{
        id: nil, 
        display_name: "Anonymous",
        profile_image: "/images/default-avatar.png"
      }
      
      %{
        id: msg.id,
        message: msg.message,
        inserted_at: msg.inserted_at,
        user: user,
        reactions: msg.reactions || []
      }
    end)
  end

  defp fallback_user do
    %{
      id: nil,
      display_name: "Anonymous",
      profile_image: "/images/default-avatar.png"
    }
  end

  defp group_consecutive(messages) do
    Enum.chunk_while(messages, [], fn msg, acc ->
      if can_group?(msg, acc) do
        {:cont, [msg | acc]}
      else
        {:cont, Enum.reverse(acc), [msg]}
      end
    end, fn
      [] -> {:cont, []}
      acc -> {:cont, Enum.reverse(acc), []}
    end)
    |> Enum.map(&format_group/1)
  end

  defp can_group?(_msg, nil), do: false # A message can't group with nil (starts a new group)
  defp can_group?(msg, prev) do
    msg_user_id = get_user_id_from_msg(msg)
    prev_user_id = get_user_id_from_msg(prev)

    # Ensure both user IDs are found and are the same
    same_user? = !is_nil(msg_user_id) && msg_user_id == prev_user_id

    # Calculate time difference only if users are the same
    time_diff_ok? =
      if same_user? do
        NaiveDateTime.diff(msg.inserted_at, prev.inserted_at, :second) < 300 # Group within 5 minutes
      else
        false
      end

    same_user? && time_diff_ok?
  end

  defp format_group(group_messages) when is_list(group_messages) and group_messages != [] do
    first = List.first(group_messages)
    user_id = get_user_id_from_msg(first)
    display_name = get_group_display_name(first)
    profile_image = get_group_profile_image(first)
    handle = get_group_handle(first) # <-- NEW helper call
    first_message_id = first.id

    %{
      id: "group-#{user_id}-#{first_message_id}",
      user_id: user_id,
      display_name: display_name,
      profile_image: profile_image,
      handle: handle, # <-- ADD handle to the map
      messages: Enum.map(group_messages, &message_struct/1),
      first_inserted: first.inserted_at,
      last_inserted: List.last(group_messages).inserted_at
    }
  end
  defp format_group([]), do: nil

  defp get_group_handle(message_map) do
    nested_handle =
      case message_map do
        %{user: user_struct} when is_struct(user_struct) -> Map.get(user_struct, :handle)
        %{user: user_map} when is_map(user_map) -> Map.get(user_map, :handle)
        _ -> nil
      end
    # Prefer nested, then top-level (though handle unlikely at top), fallback to nil
    nested_handle || Map.get(message_map, :handle)
  end

  # Gets display name, prioritizing nested :user, then top-level, then default
  defp get_group_display_name(message_map) do
    # Use dot notation for struct access, handle potential nil
    nested_name =
      case message_map do
        # Use pattern matching with dot notation if message_map itself could be a struct
        # Or more commonly, check the field directly
        %{user: user_struct} when is_struct(user_struct) ->
            Map.get(user_struct, :display_name) # Still use Map.get on the *inner* struct/map
        # Handle case where :user might be a plain map (less likely from Ecto but possible)
        %{user: user_map} when is_map(user_map) ->
            Map.get(user_map, :display_name)
        _ -> # message_map might not have :user key
          nil
      end

    nested_name || Map.get(message_map, :display_name) || "Anonymous"
  end

  # Gets profile image, prioritizing nested :user, then top-level, then default
  defp get_group_profile_image(message_map) do
    # Use dot notation for struct access, handle potential nil
    nested_image =
      case message_map do
        %{user: user_struct} when is_struct(user_struct) ->
            Map.get(user_struct, :profile_image)
        %{user: user_map} when is_map(user_map) ->
            Map.get(user_map, :profile_image)
        _ ->
          nil
      end

    nested_image || Map.get(message_map, :profile_image) || CoreComponents.default_avatar_path()
  end

  defp get_user_id(%{user: %{id: id}}), do: id
  defp get_user_id(_), do: nil

  defp get_display_name(msg) do
    cond do
      is_map(msg.user) -> msg.user.display_name || "Anonymous"
      is_binary(msg.display_name) -> msg.display_name
      true -> "Anonymous"
    end
  end

  defp get_profile_image(msg) do
    cond do
      is_map(msg.user) -> msg.user.profile_image || "/images/default-avatar.png"
      is_binary(msg.profile_image) -> msg.profile_image
      true -> "/images/default-avatar.png"
    end
  end

  defp message_struct(msg) do
    %{
      id: msg.id,
      text: msg.message, # Use :message key as per incoming data
      inserted_at: msg.inserted_at,
      # Reactions are handled at the ChatLive/MessageComponent level, not needed here
      # Include attachments (use || [] for safety if preload might fail)
      attachments: msg.attachments || []
    }
  end

  defp process_group_reactions(group) do
    group
    |> Enum.flat_map(fn msg -> 
      msg.reactions |> Enum.map(&Map.take(&1, [:emoji, :user_id, :user_handle]))
    end)
    |> Enum.group_by(& &1.emoji)
    |> Enum.map(fn {emoji, reactions} ->
      %{
        emoji: emoji,
        count: length(reactions),
        users: Enum.uniq(Enum.map(reactions, & &1.user_handle))
      }
    end)
  end

  @doc """
  Creates a new message, potentially with attachments.
  Requires either message_text or attachments_metadata to be non-empty.
  """
  def create_message(message_text, thread_id, user, replying_to_message_id \\ nil, attachments_metadata \\ []) do
    # --- Validate input: Ensure message or attachments exist ---
    has_text = message_text && String.trim(message_text) != ""
    has_attachments = attachments_metadata != []

    if !has_text and !has_attachments do
      {:error, :content_required} # Return a custom error atom
    else
      # --- Proceed with transaction ---
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:message, fn _ ->
          # Build message changeset (pass attrs directly)
          Message.changeset(%Message{}, %{
            message: message_text, # Can be nil or empty if attachments exist
            thread_id: thread_id,
            user_id: user.id,
            replying_to_message_id: replying_to_message_id
          })
        end)
        |> Ecto.Multi.run(:attachments, fn repo, %{message: message} ->
          # Prepare attachment changesets using the inserted message's ID
          attachment_changesets =
            Enum.map(attachments_metadata, fn meta ->
              Attachment.changeset(%Attachment{message_id: message.id}, meta)
            end)

          # Insert all attachments (returns {:ok, inserted_attachments} or {:error, ...})
          # Consider Repo.insert_all for better performance if supported and desired
          Enum.reduce_while(attachment_changesets, {:ok, []}, fn changeset, {:ok, acc} ->
            case repo.insert(changeset) do
              {:ok, attachment} -> {:cont, {:ok, [attachment | acc]}}
              {:error, error_changeset} -> {:halt, {:error, error_changeset}}
            end
          end)
        end)
        |> Ecto.Multi.run(:thread_preview, fn _repo, %{message: message} ->
            # Fetch preview data for the parent thread
            case get_thread_preview(message.thread_id) do
               nil -> {:error, :thread_not_found_for_preview} # Should not happen
               preview -> {:ok, preview}
            end
        end)

      Repo.transaction(multi)
      |> case do
        {:ok, %{message: message, attachments: attachments, thread_preview: thread_preview}} ->
          # Preload necessary associations for the broadcast/return value
          message = Repo.preload(message, [:user, replying_to: [:user], attachments: []]) # Preload attachments too
          # Manually assign the just-inserted attachments to the preloaded list
          message = %{message | attachments: Enum.reverse(attachments)}
          Endpoint.broadcast!(PubSubTopics.thread_list_updates(), "thread_updated", thread_preview)

          {:ok, message}

        {:error, :message, changeset, _} ->
          {:error, changeset} # Error creating message

        {:error, :attachments, attachment_error_changeset, _} ->
          {:error, attachment_error_changeset} # Error creating attachments
        {:error, :thread_preview, reason, _} ->
          Logger.error("Failed to get thread preview after message creation: #{inspect(reason)}")
          {:error, :preview_fetch_failed}

        # Handle other potential Multi errors
        {:error, failed_operation, failed_value, _changes_so_far} ->
           Logger.error("Failed message/attachment creation. Op: #{failed_operation}, Value: #{inspect(failed_value)}")
           {:error, :transaction_failed}
      end
    end
  end

  @doc """
  Deletes a message if the user owns it.
  Returns {:ok, message} or {:error, reason}.
  Reasons can be :not_found, :unauthorized.
  """
  def delete_message(message_id, user_id) when is_integer(message_id) and is_integer(user_id) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      message ->
        if message.user_id == user_id do
          # TODO: Add moderator/admin check here in the future
          Repo.delete(message) # Returns {:ok, message} or {:error, changeset} on failure
        else
          {:error, :unauthorized}
        end
    end
  end
  def delete_message(message_id_str, user_id) when is_binary(message_id_str) do
     case Integer.parse(message_id_str) do
       {int_id, ""} -> delete_message(int_id, user_id)
       _ -> {:error, :invalid_id}
     end
  end

  @doc """
  Updates a message's content if the user owns it.

  Returns `{:ok, message}` or `{:error, reason}`.
  Reasons can be :not_found, :unauthorized, or an error changeset.
  """
  def update_message(message_id, user_id, new_content) when is_integer(message_id) and is_integer(user_id) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      message ->
        if message.user_id == user_id do
          # TODO: Add moderator/admin check here in the future
          message
          |> Message.changeset(%{message: new_content}) # Use existing changeset
          |> Repo.update() # Returns {:ok, message} or {:error, changeset}
        else
          {:error, :unauthorized}
        end
    end
  end
  def update_message(message_id_str, user_id, new_content) when is_binary(message_id_str) do
     case Integer.parse(message_id_str) do
       {int_id, ""} -> update_message(int_id, user_id, new_content)
       _ -> {:error, :invalid_id}
     end
  end

  @doc """
  Creates a new topic
  """
  def create_topic(name, path) do
    Repo.insert(%Topic{ name: name, path: path }, on_conflict: :nothing)
  end

  @doc """
  Gets a topic by path
  """
  def get_topic(path) do
    query = from p in Topic,
      select: struct(p, [:id, :name, :path]),
      where: p.path == ^path
    Repo.one(query)
  end

  @doc """
  Sets all threads with nil topic to the main topic
  """
  def set_main_topic do
    main_topic = get_topic("main")

    query = from p in Thread,
      where: is_nil(p.topic_id) and is_nil(p.user_id),
      update: [set: [topic_id: ^main_topic.id]]
    Repo.update_all(query, [])
  end

  @doc """
  Sets all messages with nil user to the first user
  """
  def set_message_default_user do
    query = from p in Message,
      where: is_nil(p.user_id),
      update: [set: [user_id: 1]]
    Repo.update_all(query, [])
  end

  @doc """
  Lists all topics
  """
  def list_topics do
    query = from p in Topic,
      select: struct(p, [:id, :name, :path])
    Repo.all(query)
  end

  def add_reaction(message_id, user_id, emoji) when is_binary(message_id) do
    add_reaction(String.to_integer(message_id), user_id, emoji)
  end

  def add_reaction(message_id, user_id, emoji) do
    Repo.transaction(fn ->
      # Check existing state atomically
      case Repo.get_by(Reaction,
             message_id: message_id,
             user_id: user_id,
             emoji: emoji
           ) do
        nil ->
          # Insert with conflict protection
          {:ok, inserted} = 
            Repo.insert(
              %Reaction{
                message_id: message_id,
                user_id: user_id,
                emoji: emoji
              },
              # Handle race conditions between optimistic update and actual DB write
              on_conflict: :nothing,
              returning: true
            )

          if inserted do
            :add
          else
            # Reaction was already added by another client - confirm existing
            :confirmed
          end

        reaction ->
          # Delete with version checking if needed
          Repo.delete!(reaction)
          :remove
      end
    end)
  end

  defp get_thread_id(message_id) do
    Message
    |> where([m], m.id == ^message_id)
    |> select([m], m.thread_id)
    |> Repo.one()
  end

  def get_reactions(message_ids) when is_list(message_ids) do
    from(r in Reaction,
      where: r.message_id in ^message_ids,
      group_by: [r.message_id, r.emoji],
      select: {r.message_id, r.emoji, sum(r.count)}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {mid, emoji, count}, acc ->
      Map.update(acc, mid, %{emoji => count}, &Map.put(&1, emoji, count))
    end)
  end

  @doc """
  Fetches raw reaction data (message_id, emoji, user_id) for a batch of message IDs.
  """
  def get_reactions_for_message_batch(message_ids) when is_list(message_ids) do
    # Handle empty list to avoid querying with empty 'IN' clause
    if message_ids == [] do
      []
    else
      from(r in Reaction,
        where: r.message_id in ^message_ids,
        select: {r.message_id, r.emoji, r.user_id} # Select raw tuples
      )
      |> Repo.all()
    end
  end
  def get_reactions_for_message_batch(_), do: [] # Catch non-list input just in case

  def get_reactions_for_messages(message_ids) do
    from(r in Reaction,
      where: r.message_id in ^message_ids,
      group_by: [r.message_id, r.emoji],
      select: %{
        message_id: r.message_id,
        emoji: r.emoji,
        count: count(r.id),
        users: fragment("ARRAY_AGG(?)::integer[]", r.user_id)
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.message_id, fn reaction ->
      %{reaction | users: MapSet.new(reaction.users)}
    end)
  end

  def get_user_reactions(message_ids, user_id) do
    from(r in Reaction,
      where: r.message_id in ^message_ids and r.user_id == ^user_id,
      select: {r.message_id, r.emoji}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {msg_id, emoji}, acc ->
      Map.update(acc, msg_id, MapSet.new([emoji]), &MapSet.put(&1, emoji))
    end)
  end

  def get_reactions_for_messages(message_ids) do
    from(r in Reaction,
      where: r.message_id in ^message_ids,
      group_by: [r.message_id, r.emoji],
      select: %{
        message_id: r.message_id,
        emoji: r.emoji,
        count: count(r.id),
        users: fragment("ARRAY_AGG(?)", r.user_id)
      })
    |> Repo.all()
    |> Enum.group_by(& &1.message_id, & &1)
  end

  def get_user_reactions(message_ids, user_id) do
    from(r in Reaction,
      where: r.message_id in ^message_ids and r.user_id == ^user_id,
      select: {r.message_id, r.emoji})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Main entry point for sharing. Delegates based on target type.
  Target ID should be the ID of the Topic or User profile being shared TO.
  """
  def share_item(item_type, item_id, target_type, target_id, sharer_user) do
    # Determine if it's a thread or message being shared
    case item_type do
      :thread ->
        # Delegate, passing specific target field based on target_type
        share_thread(item_id, target_type, target_id, sharer_user)
      :message ->
        # Fetch the message to get its thread_id
        message = Repo.get(Message, item_id)

        if !message do
          {:error, :original_message_not_found}
        else
          thread_id = message.thread_id

          # --- Query for the actual first message ID ---
          first_message_id_in_thread =
            from(m in Message,
              where: m.thread_id == ^thread_id,
              order_by: [asc: m.inserted_at, asc: m.id], # Use ID as tie-breaker
              limit: 1,
              select: m.id
            )
            |> Repo.one()
          # --- End Query ---

          # Check if the message being shared IS the first message
          if first_message_id_in_thread == item_id do
             # Treat as sharing the thread
             IO.puts("Message #{item_id} is first in thread #{thread_id}, treating as thread share.")
             share_thread(thread_id, target_type, target_id, sharer_user)
          else
             # Share the specific message (spin-off logic)
             IO.puts("Message #{item_id} is NOT first in thread #{thread_id}, treating as message share.")
             share_message(item_id, target_type, target_id, sharer_user)
          end
        end
      _ ->
        {:error, :invalid_item_type}
    end
  end

  # Helper to share a message (potentially creating a spin-off)
  defp share_message(message_id, target_type, target_id, sharer_user) do
    # Wrap the check-and-create/share logic in a transaction
    Repo.transaction(fn ->
      # Check for existing spin-off *within* the transaction
      case find_spin_off_thread(message_id) do
        # --- Spin-off ALREADY EXISTS ---
        %Thread{id: spin_off_thread_id} ->
          IO.puts("Spin-off exists for message #{message_id}, sharing thread #{spin_off_thread_id}")
          # Use Multi for consistency within transaction, delegate to helper
          Ecto.Multi.new()
          |> share_thread_multi(spin_off_thread_id, target_type, target_id, sharer_user)
          # Insert operation returns {:ok, share} or {:error, changeset}
          # We might want to return the Share struct or just :ok
          |> Repo.transaction() # Execute the share_thread multi
          |> case do
               {:ok, %{share: share}} -> {:ok, share} # Share created successfully
               {:error, :share, changeset, _} -> {:error, changeset} # Error creating share
               # Handle other multi errors if share_thread_multi grows
             end

        # --- Spin-off DOES NOT EXIST (Attempt Creation) ---
        nil ->
          IO.puts("Attempting to create new spin-off for message #{message_id}")
          # Fetch original message details (still needed)
          original_message = Repo.get(Message, message_id) |> Repo.preload(:user)

          if !original_message do
            Repo.rollback(:original_message_not_found) # Rollback transaction
          else
            # Generate title/content
            original_author_name = original_message.user.display_name || "Someone"
            spin_off_title = "Shared: #{WindyfallWeb.TextHelpers.truncate(original_message.message, 50)}"
            spin_off_content = """
            Shared message by #{original_author_name}:

            > #{original_message.message}

            [Link to original](#{generate_message_link(original_message)})
            """

            # --- Build Changeset for Spin-off Thread ---
            thread_changeset =
              %Thread{}
              |> Thread.changeset(
                   %{ # Basic attrs
                     title: spin_off_title,
                     creator_id: sharer_user.id,
                     spin_off_of_message_id: message_id
                   },
                   target_type, # Pass context type
                   target_id    # Pass context id
                 )

            # --- Attempt to Insert Spin-off Thread ---
            case Repo.insert(thread_changeset) do
              # --- SUCCESS: Spin-off Thread Created ---
              {:ok, spin_off_thread} ->
                IO.inspect "sipn off insert ok"
                # Create the first message (the quote)
                case create_message(spin_off_content, spin_off_thread.id, sharer_user) do
                   {:ok, first_message} ->
                      # Update counts - MUST return the updated thread struct for the transaction result
                      {:ok, update_thread_counts(spin_off_thread, first_message)}
                   {:error, msg_changeset} ->
                      IO.inspect msg_changeset, label: "error creating message in spin_off thread"
                      Repo.rollback({:changeset, msg_changeset}) # Rollback if message creation fails
                end

              # --- ERROR: Failed to Insert Spin-off Thread ---
              {:error, changeset} ->
                # Check if it's the unique constraint violation
                IO.inspect changeset, label: "errored in insert spin-off"
                is_unique_violation = Enum.any?(changeset.errors, fn {field, details} ->
                   field == :spin_off_of_message_id and String.contains?(elem(details, 0), "unique") # Basic check
                   # Or check constraint name if more specific:
                   # constraint = details[:constraint]
                   # constraint_name = details[:constraint_name]
                   # constraint == :unique and constraint_name == :threads_unique_spin_off_idx
                end)

                if is_unique_violation do
                  # CONCURRENCY HIT: Spin-off was created by another process.
                  IO.warn("Concurrency hit: Spin-off for message #{message_id} created concurrently. Retrying share.")
                  # Retry finding the spin-off *within the same transaction*
                  case find_spin_off_thread(message_id) do
                    %Thread{id: concurrent_spin_off_id} ->
                      # Found the concurrently created thread, now share *it*
                       Ecto.Multi.new()
                       |> share_thread_multi(concurrent_spin_off_id, target_type, target_id, sharer_user)
                       |> Repo.transaction() # Execute the share_thread multi
                       |> case do
                            {:ok, %{share: share}} -> {:ok, share} # Share created successfully
                            {:error, :share, cs, _} -> Repo.rollback(cs) # Error creating share, rollback outer tx
                          end
                    nil ->
                      # Should be very rare: Unique violation but then couldn't find it? Rollback.
                      IO.error("Unique constraint hit for spin-off msg #{message_id}, but failed to re-find thread.")
                      Repo.rollback(:spin_off_creation_race_condition_unresolved)
                  end
                else
                  # Different insertion error (validation, etc.)
                  Repo.rollback({:changeset, changeset})
                end
                # End if is_unique_violation
            end
            # --- End Attempt Insert ---
          end
          # End if !original_message else block
      end
      # End case find_spin_off_thread
    end) # End Repo.transaction
    # The result of Repo.transaction will be the final {:ok, result} or {:error, reason}
  end

  # Helper for share_thread logic within a Multi (used above)
  defp share_thread_multi(multi, thread_id, target_type, target_id, sharer_user) do
    attrs = %{
      user_id: sharer_user.id,
      thread_id: thread_id
    }
    attrs = case target_type do
      :topic -> Map.put(attrs, :target_topic_id, target_id)
      :user  -> Map.put(attrs, :target_user_id, target_id)
      _      -> nil # Invalid target type handled before calling this usually
    end

    # Use Multi.insert
    Ecto.Multi.insert(multi, :share, Share.changeset(%Share{}, attrs))
  end

  # Ensure share_thread still exists for direct calls if needed elsewhere,
  # potentially refactor it to use share_thread_multi as well.
  defp share_thread(thread_id, target_type, target_id, sharer_user) do
     Ecto.Multi.new()
     |> share_thread_multi(thread_id, target_type, target_id, sharer_user)
     |> Repo.transaction() # Execute the multi
     |> case do
          {:ok, %{share: share}} -> {:ok, share}
          {:error, :share, changeset, _} -> {:error, changeset}
          # Handle other potential multi errors
        end
  end

  defp find_spin_off_thread(original_message_id) do
    from(t in Thread, where: t.spin_off_of_message_id == ^original_message_id, limit: 1)
    |> Repo.one()
  end

  defp generate_message_link(message) do
    thread = Repo.get(Thread, message.thread_id) |> Repo.preload([:topic, :user, :creator])

    if thread do
      # Determine base path based on available context info
      base_path = get_thread_base_path(thread)
      "#{base_path}/thread/#{thread.id}#message-#{message.id}"
    else
      "#"
    end
  end

# Helper function to determine the base path
defp get_thread_base_path(thread) do
  cond do
    # Check topic context first (ensure preload worked)
    thread.topic_id && thread.topic ->
      ~p"/t/#{thread.topic.path}"

    # Check user context next (ensure preload worked)
    thread.user_id && thread.user ->
      context_user = thread.user
      if context_user.handle && context_user.handle != "" do
        ~p"/u/#{context_user.handle}"
      else
        ~p"/uid/#{thread.user_id}"
      end

    # Fallbacks if preloads failed or no context (latter shouldn't happen)
    thread.topic_id ->
      IO.warn("Thread #{thread.id} missing preloaded :topic for link generation")
      ~p"/chat" # Or maybe try fetching topic path here? Risky.
    thread.user_id ->
      IO.warn("Thread #{thread.id} missing preloaded :user for link generation")
      ~p"/uid/#{thread.user_id}" # Fallback to ID route even without handle check
    true ->
      IO.warn("Thread #{thread.id} missing context for link generation")
      ~p"/chat"
  end
end

  def get_thread_preview(thread_id) do
    default_avatar = WindyfallWeb.CoreComponents.default_avatar_path()
    from(t in Thread,
      where: t.id == ^thread_id,
      # --- JOIN/SELECT CREATOR ---
      join: c in assoc(t, :creator), # Join creator
      left_join: m in Message, on: m.thread_id == t.id,
      group_by: [t.id, c.id], # Group by creator too
      # --- END JOIN/SELECT ---
      limit: 1,
      select: %{
        id: t.id,
        title: t.title,
        # --- Use creator fields for author ---
        creator_id: t.creator_id,
        author_name: coalesce(c.display_name, "Anonymous"),
        author_avatar: coalesce(c.profile_image, ^default_avatar),
        user_handle: c.handle, # Get handle directly from creator
        # --- End author fields ---
        first_message_preview: fragment("""
               SUBSTRING( (ARRAY_AGG(? ORDER BY ? ASC) FILTER (WHERE ? IS NOT NULL))[1] FROM 1 FOR 280 )
               """, m.message, m.inserted_at, m.message),
        message_count: count(m.id),
        last_message_at: max(m.inserted_at),
        inserted_at: t.inserted_at,
        spin_off_of_message_id: t.spin_off_of_message_id,
        topic_id: t.topic_id,
        user_id: t.user_id
        # Add context fields if needed by preview logic later
        # topic_id: t.topic_id,
        # user_id: t.user_id
      }
    ) |> Repo.one()
  end

  @doc """
  Adds a bookmark for a user and thread. Idempotent.
  Returns {:ok, :bookmarked} on success or if already bookmarked.
  """
  def add_bookmark(user_id, thread_id) when is_integer(user_id) and is_integer(thread_id) do
    %Bookmark{}
    |> Bookmark.changeset(%{user_id: user_id, thread_id: thread_id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :thread_id])
    |> case do
      {:ok, _bookmark} -> {:ok, :bookmarked}
      # Error usually means conflict (already exists) or FK violation (user/thread gone)
      {:error, _changeset} -> {:ok, :bookmarked} # Treat conflict as success
    end
  end

  @doc """
  Removes a bookmark for a user and thread.
  Returns {:ok, :unbookmarked} on success or if not found.
  """
  def remove_bookmark(user_id, thread_id) when is_integer(user_id) and is_integer(thread_id) do
    from(b in Bookmark, where: b.user_id == ^user_id and b.thread_id == ^thread_id)
    |> Repo.delete_all()
    # delete_all always returns {count, nil}, so we don't check the result here
    {:ok, :unbookmarked}
  end

  @doc """
  Toggles a bookmark for a user and thread.
  Returns {:ok, :bookmarked}, {:ok, :unbookmarked}, or {:error, reason}.
  """
  def toggle_bookmark(user_id, thread_id) when is_integer(user_id) and is_integer(thread_id) do
    case Repo.get_by(Bookmark, user_id: user_id, thread_id: thread_id) do
      nil -> add_bookmark(user_id, thread_id) # Not bookmarked, so add it
      _bookmark -> remove_bookmark(user_id, thread_id) # Is bookmarked, so remove it
    end
  end

  @doc """
  Lists all threads bookmarked by a given user.
  Returns a list of thread maps, similar to list_threads_for_context.
  """
  def list_bookmarked_threads(user_id) when is_integer(user_id) do
    default_avatar = WindyfallWeb.CoreComponents.default_avatar_path()

    # Start with threads, join bookmarks, then join creator and messages for details
    from(t in Thread,
      # Join bookmarks specific to the user
      join: b in Bookmark, on: b.thread_id == t.id and b.user_id == ^user_id,
      # Join creator for author details
      join: c in assoc(t, :creator),
      # Left join messages to get counts/previews even if count is 0 (though unlikely)
      left_join: m in Message, on: m.thread_id == t.id,
      group_by: [t.id, c.id, b.inserted_at], # Group by thread, creator, and bookmark time
      # Order by when the bookmark was created (newest first)
      order_by: [desc: b.inserted_at],
      select: %{
        # Select fields matching list_threads_for_context for consistency
        id: t.id,
        title: t.title,
        message_count: count(m.id),
        last_message_at: max(m.inserted_at),
        inserted_at: t.inserted_at, # Thread creation time
        creator_id: t.creator_id,
        author_name: coalesce(c.display_name, "Anonymous"),
        author_avatar: coalesce(c.profile_image, ^default_avatar),
        user_handle: c.handle,
        topic_id: t.topic_id,
        user_id: t.user_id,
        spin_off_of_message_id: t.spin_off_of_message_id,
        first_message_preview: fragment("""
          SUBSTRING( (ARRAY_AGG(? ORDER BY ? ASC) FILTER (WHERE ? IS NOT NULL))[1] FROM 1 FOR 280 )
          """, m.message, m.inserted_at, m.message),
        # Add bookmark timestamp if needed
        bookmarked_at: b.inserted_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets the bookmark status for a user across multiple threads.
  Returns a MapSet of thread IDs that the user has bookmarked.
  """
  def get_user_bookmark_status(user_id, thread_ids) when is_integer(user_id) and is_list(thread_ids) do
    # Handle empty list to avoid empty 'IN' query
    if thread_ids == [] do
      MapSet.new()
    else
      from(b in Bookmark,
        where: b.user_id == ^user_id and b.thread_id in ^thread_ids,
        select: b.thread_id
      )
      |> Repo.all()
      |> MapSet.new()
    end
  end
  # Fallback for non-list thread_ids
  def get_user_bookmark_status(_user_id, _thread_ids), do: MapSet.new()
end
