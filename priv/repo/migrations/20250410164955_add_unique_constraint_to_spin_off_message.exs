defmodule Windyfall.Repo.Migrations.AddUniqueConstraintToSpinOffMessage do
  use Ecto.Migration

  def change do
    # Add a unique index on spin_off_of_message_id, but only for non-NULL values.
    # This allows many threads to NOT be spin-offs (NULL), but only one thread
    # per original message ID.
    # Syntax is for PostgreSQL.
    drop index(:threads, [:spin_off_of_message_id])

    create unique_index(:threads, [:spin_off_of_message_id],
             where: "spin_off_of_message_id IS NOT NULL",
             name: :threads_unique_spin_off_idx
           )
  end

  def down do
    drop index(:threads, [:spin_off_of_message_id], name: :threads_unique_spin_off_idx)
    create index(:threads, [:spin_off_of_message_id])
  end
end
