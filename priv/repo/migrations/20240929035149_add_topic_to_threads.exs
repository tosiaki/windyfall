defmodule Windyfall.Repo.Migrations.AddTopicToThreads do
  use Ecto.Migration

  def change do
    alter table(:threads) do
      add :topic_id, references(:topics)
    end
  end
end
