defmodule Windyfall.Repo.Migrations.UniqueIndexGamePlaySessions do
  use Ecto.Migration

  def change do
    create unique_index(:game_plays, [:session])
  end
end
