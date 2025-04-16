defmodule Windyfall.Repo.Migrations.AddReactionsAndParentMessage do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :parent_id, references(:messages, on_delete: :nothing)
    end

    create table(:reactions) do
      add :emoji, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:reactions, [:user_id])
    create index(:reactions, [:message_id])
    create unique_index(:reactions, [:user_id, :message_id, :emoji])
  end
end
