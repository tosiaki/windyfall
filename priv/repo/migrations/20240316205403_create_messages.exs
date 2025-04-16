defmodule Windyfall.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :message, :string, null: false

      timestamps()
    end
  end
end
