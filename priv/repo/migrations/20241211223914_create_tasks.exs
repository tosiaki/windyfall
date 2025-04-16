defmodule Windyfall.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :name, :string
      add :user_id, references(:users)

      timestamps(type: :utc_datetime)
    end
  end
end
