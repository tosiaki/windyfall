defmodule Windyfall.Repo.Migrations.AddSpinOffToThreads do
  use Ecto.Migration

  def change do
    alter table(:threads) do
      # Add the column to store the original message ID for spin-offs
      add :spin_off_of_message_id, references(:messages, on_delete: :nilify_all), null: true
    end

    # Add an index for faster lookups when checking if a spin-off exists
    create index(:threads, [:spin_off_of_message_id])
  end
end
