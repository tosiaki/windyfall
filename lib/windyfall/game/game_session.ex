defmodule Windyfall.Game.GameSession do
  use GenServer

  import Ecto.Query, warn: false
  alias Windyfall.Repo
  alias Windyfall.Game.GamePlay

  def start_link(session) do
    GenServer.start_link(__MODULE__, session, name: {:via, Registry, {:session_registry, session}})
  end

  def update_data(pid, updated_data) do
    GenServer.cast(pid, {:update_data, updated_data})
  end

  def get_data(pid) do
    GenServer.call(pid, :get_data)
  end

  def end_session(pid) do
    GenServer.cast(pid, :end)
  end

  def init(session) do
    # Fetch existing game state from DB
    query = from p in GamePlay,
      select: p.game_state,
      where: p.session == ^session

    # Load or initialize data
    data =
      case Repo.one(query) do
        nil ->
          # DB record doesn't exist - initialize NEW state with "score"
          %{"score" => 0, "player_name" => "Guest #{Windyfall.Accounts.Guest.new_id()}"}
        db_game_state ->
          # DB record exists - handle potential old "flow" key
          %{
            # Prioritize "score", fallback to "flow", default to 0
            "score" => Map.get(db_game_state, "score", Map.get(db_game_state, "flow", 0)),
            # Load player name or provide default
            "player_name" => Map.get(db_game_state, "player_name", "Guest #{Windyfall.Accounts.Guest.new_id()}")
          }
          |> Map.merge(db_game_state) # Merge other saved fields
          |> Map.delete("flow") # Optionally remove the old flow key after loading
      end

    # Start save timer
    :timer.send_interval(20000, self(), {:save, session})

    # Start GenServer with the corrected data map
    {:ok, data}
  end

  def handle_call(:get_data, _from, data) do
    {:reply, data, data}
  end

  def handle_cast({:update_data, updated_data}, _data) do
    {:noreply, updated_data}
  end

  def handle_info({:save, session}, data) do
    # The 'data' map comes from GameLive via update_session,
    # so it should already have the "score" key.
    # The on_conflict strategy correctly updates the game_state column.
    Repo.insert!(
      %GamePlay{session: session, game_state: data},
      on_conflict: [set: [game_state: data]],
      conflict_target: :session
    )
    {:noreply, data}
  end
end
