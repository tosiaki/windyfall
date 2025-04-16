defmodule Windyfall.Repo.Migrations.CreateGamePlays do
  use Ecto.Migration

  def change do
    create table(:game_plays) do
      add :session, :string, null: false
      add :user_id, references(:users)
      add :game_state, :map, default: %{}

      timestamps()
    end
  end
end
