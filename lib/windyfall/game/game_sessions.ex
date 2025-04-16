defmodule Windyfall.Game.GameSessions do
  use GenServer
  @me __MODULE__

  import Ecto.Query, warn: false
  alias Windyfall.Repo
  alias Windyfall.Game.GameSession
  alias Windyfall.Game.GamePlay

  def start_link(_) do
    Registry.start_link(keys: :unique, name: :session_registry)
    GenServer.start_link(__MODULE__, nil, name: @me)
  end

  def get_session(session) do
    GenServer.call(@me, {:get_session, session})
  end

  def update_session(session_id, data) do
    [{session_pid, _}] = Registry.lookup(:session_registry, session_id)
    GameSession.update_data(session_pid, data)
  end

  def remove_session(session) do
    [{session_pid, _}] = Registry.lookup(:session_registry, session)
    GameSession.end_session(session_pid)
  end

  def all_sessions do
    GenServer.call(@me, :all_sessions)
  end

  def init(_) do
    {:ok, %{all_sessions: nil}}
  end

  def handle_call(:all_sessions, _from, state) do
    all_sessions = case state.all_sessions do
      nil ->
        # Corrected Query for Leaderboard
        query = from p in GamePlay,
          # Use COALESCE to prioritize 'score', then 'flow', default to 0 if neither exists
          # Ensure we cast to a numeric type (like DECIMAL or float) for proper ordering.
          # Note: ->> extracts as text, -> extracts as JSON. Use ->> for comparison/casting.
          select: %{
            "player_name" => fragment("? ->> 'player_name'", p.game_state),
            "score" => fragment("COALESCE((? ->> 'score')::DECIMAL, (? ->> 'flow')::DECIMAL, 0)", p.game_state, p.game_state)
          },
          # Order by the calculated score
          order_by: [desc: fragment("COALESCE((? ->> 'score')::DECIMAL, (? ->> 'flow')::DECIMAL, 0)", p.game_state, p.game_state)]
          # Optional: Add a limit if the leaderboard gets too long
          # limit: 50

        Repo.all(query) # Repo.all will return a list of maps with "player_name" and "score" keys

      cached_sessions ->
        # If using caching, ensure the cached data also has the correct structure
        cached_sessions
    end
    {:reply, all_sessions, Map.put(state, :all_sessions, all_sessions)}
  end

  def handle_call({:get_session, session}, _from, state) do
    data = case Registry.lookup(:session_registry, session) do
      [] ->
        {:ok, pid} = GameSession.start_link(session)
        GameSession.get_data(pid)
      [{session_pid, _}] -> GameSession.get_data(session_pid)
    end
    {:reply, data, state}
  end
end
