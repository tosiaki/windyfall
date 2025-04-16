defmodule Windyfall.Repo.Migrations.UniqueIndexTopicPaths do
  use Ecto.Migration

  def change do
    create unique_index(:topics, [:path])
  end
end
