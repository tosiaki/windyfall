defmodule Windyfall.Repo.Migrations.AddCreatorAndContextConstraintToThreads do
  use Ecto.Migration

  def change do
    # Add creator_id, initially allowing NULLs for backfill
    alter table(:threads) do
      add :creator_id, references(:users, on_delete: :nilify_all), null: true
    end

    # Add index for creator_id
    create index(:threads, [:creator_id])

    # --- BACKFILL LOGIC (Run as separate script/task before making creator_id NOT NULL) ---
    # We will run this logic outside the migration transaction later.

    # Add CHECK constraint to ensure exactly one context FK is set
    # Ensure this runs *after* backfill logic corrects the user_id/topic_id columns
    # We'll add this constraint in a *separate* migration after backfilling.
    # For now, just add the creator_id column and index.
  end
end
