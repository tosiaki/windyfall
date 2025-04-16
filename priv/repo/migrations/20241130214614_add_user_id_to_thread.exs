defmodule Windyfall.Repo.Migrations.AddUserIdToThread do
  use Ecto.Migration

  def change do
    alter table(:threads) do
      add :user_id, references(:users)
    end
  end
end
