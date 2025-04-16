defmodule Windyfall.Messages.Reaction do
  use Ecto.Schema

  schema "reactions" do
    field :emoji, :string
    belongs_to :user, Windyfall.Accounts.User
    belongs_to :message, Windyfall.Messages.Message

    timestamps()
  end
end
