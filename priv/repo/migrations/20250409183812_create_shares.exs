defmodule Windyfall.Repo.Migrations.CreateShares do
  use Ecto.Migration

  def change do
    create table(:shares) do
      add :user_id, references(:users, on_delete: :delete_all), null: false # User who shared
      add :thread_id, references(:threads, on_delete: :delete_all), null: false # Thread being shared (original or spin-off)

      # --- Use Multiple Foreign Keys ---
      add :target_topic_id, references(:topics, on_delete: :delete_all), null: true
      add :target_user_id, references(:users, on_delete: :delete_all), null: true # User whose profile it's shared on
      # --- End Multiple Foreign Keys ---

      timestamps()
    end

    # Indexes
    create index(:shares, [:user_id])
    create index(:shares, [:thread_id])
    create index(:shares, [:target_topic_id])
    create index(:shares, [:target_user_id])

    # --- Add CHECK Constraint (PostgreSQL specific) ---
    # Ensures exactly one of target_topic_id or target_user_id is NOT NULL
    execute """
    ALTER TABLE shares
    ADD CONSTRAINT shares_only_one_target_check
    CHECK (
      (CASE WHEN target_topic_id IS NULL THEN 0 ELSE 1 END) +
      (CASE WHEN target_user_id IS NULL THEN 0 ELSE 1 END)
      = 1
    )
    """
    # For other databases, this constraint might need different syntax or
    # rely solely on application-level validation in the changeset.
    # --- End CHECK Constraint ---

    create unique_index(:shares, [:user_id, :thread_id, :target_topic_id], name: :shares_unique_user_thread_topic_target_idx, where: "target_user_id IS NULL")
    create unique_index(:shares, [:user_id, :thread_id, :target_user_id], name: :shares_unique_user_thread_user_target_idx, where: "target_topic_id IS NULL")
  end

  def down do
    execute "ALTER TABLE shares DROP CONSTRAINT shares_only_one_target_check"
    drop table(:shares)
  end
end
