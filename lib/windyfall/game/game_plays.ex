defmodule Windyfall.Game.GamePlay do
  use Ecto.Schema

  schema "game_plays" do
    field :session, :string
    field :game_state, :map

    belongs_to :user, Windyfall.Accounts.User

    timestamps()
  end
end
