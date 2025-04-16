defmodule Windyfall.Repo.Migrations.RenameChannelsToThreads do
  use Ecto.Migration

  def up do
    rename table(:channels), to: table(:threads)
  end

  def down do
    rename table(:threads), to: table(:channels)
  end
end
