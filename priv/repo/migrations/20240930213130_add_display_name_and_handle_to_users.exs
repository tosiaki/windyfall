defmodule Windyfall.Repo.Migrations.AddDisplayNameAndHandleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :display_name, :string
      add :handle, :string
    end
  end
end
