defmodule WindyfallWeb.Presence do
  use Phoenix.Presence,
    otp_app: :windyfall,
    pubsub_server: Windyfall.PubSub

  def track_active_message(pid, message_id) do
    track(pid, "messages", message_id, %{})
  end

  def list_active_message_ids do
    list("messages")
    |> Map.keys()
    |> Enum.map(&String.to_integer/1)
  end
end
