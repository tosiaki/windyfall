defmodule Windyfall.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :title, :string, null: false

      timestamps()
    end
  end
end
