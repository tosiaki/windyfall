defmodule Windyfall.Repo.Migrations.AddThreadMetadata do
  use Ecto.Migration

  def change do
    alter table(:threads) do
      add :message_count, :integer, default: 0, null: false
      add :last_message_at, :naive_datetime
    end
  end
end
