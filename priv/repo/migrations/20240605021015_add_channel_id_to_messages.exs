defmodule Windyfall.Repo.Migrations.AddChannelIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :channel_id, references(:channels)
    end
  end
end
