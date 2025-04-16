defmodule Windyfall.GameSession do
  alias Windyfall.Accounts.Guest

  import Plug.Conn
  def init(opts), do: opts
  def call(conn, _opts) do
    conn = fetch_cookies(conn, encrypted: ["game-session"])

    cookie = conn.cookies["game-session"]

    { conn, session_id } = get_session_id(conn, cookie)

    put_session(conn, :game_session, session_id)
  end

  defp get_session_id(conn, nil) do
    new_id = Guest.new_session
    { put_resp_cookie(conn, "game-session", new_id, encrypt: true), new_id }
  end

  defp get_session_id(conn, cookie) do
    { conn, cookie }
  end
end
