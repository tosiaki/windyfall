defmodule Windyfall.Messages.Bookmark do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bookmarks" do
    belongs_to :user, Windyfall.Accounts.User
    belongs_to :thread, Windyfall.Messages.Thread

    timestamps()
  end

  @doc false
  def changeset(bookmark, attrs) do
    bookmark
    |> cast(attrs, [:user_id, :thread_id])
    |> validate_required([:user_id, :thread_id])
    # The unique constraint is handled by the database index
    |> unique_constraint([:user_id, :thread_id], name: :bookmarks_user_id_thread_id_index)
  end
end
