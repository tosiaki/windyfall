defmodule Windyfall.Repo do
  use Ecto.Repo,
    otp_app: :windyfall,
    adapter: Ecto.Adapters.Postgres
end
