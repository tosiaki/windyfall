defmodule Windyfall.Repo.Migrations.CreateTopics do
  use Ecto.Migration

  def change do
    create table(:topics) do
      add :path, :string
      add :name, :string

      timestamps(type: :utc_datetime)
    end
  end
end
