defmodule Windyfall.Repo.Migrations.UpdateUserHandlesUniqueness do
  use Ecto.Migration

  def up do
    # Step 1: Convert existing empty strings to NULL
    # Use execute for raw SQL update
    execute "UPDATE users SET handle = NULL WHERE handle = ''"

    # Step 2: Add a unique index, ignoring NULLs and empty strings, case-insensitive
    # Using lower() makes the index case-insensitive.
    # The WHERE clause ensures uniqueness only applies to actual handles.
    execute """
    CREATE UNIQUE INDEX users_handle_unique_idx
    ON users (lower(handle))
    WHERE handle IS NOT NULL AND handle <> ''
    """

    # Optional: Add a CHECK constraint for handle format if desired (e.g., alphanumeric + underscore)
    # execute """
    # ALTER TABLE users
    # ADD CONSTRAINT users_handle_format_check
    # CHECK (handle ~ '^[a-zA-Z0-9_]+$')
    # """
  end

  def down do
    # Optional: Drop CHECK constraint if added
    # execute "ALTER TABLE users DROP CONSTRAINT users_handle_format_check"

    # Drop the unique index
    execute "DROP INDEX users_handle_unique_idx"

    # Reverting blank strings is harder, maybe just leave them as NULL on rollback
    # Or revert NULLs created from blanks back to blanks if critical
    # execute "UPDATE users SET handle = '' WHERE handle IS NULL AND /* some condition to identify originally blank ones */"
    # Simpler to just drop index on rollback.
  end
end
