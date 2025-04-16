defmodule Windyfall.Repo.Migrations.CreateBookmarks do
  use Ecto.Migration

  def change do
    create table(:bookmarks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :thread_id, references(:threads, on_delete: :delete_all), null: false

      timestamps()
    end

    # Ensure a user can only bookmark a thread once
    create index(:bookmarks, [:user_id, :thread_id], unique: true)
    # Index for efficient lookup of a user's bookmarks
    create index(:bookmarks, [:user_id])
    # Index potentially useful if looking up who bookmarked a thread (less common)
    # create index(:bookmarks, [:thread_id])
  end
end
