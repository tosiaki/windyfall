defmodule Windyfall.Repo.Migrations.RenameMessageChannelId do
  use Ecto.Migration

  def up do
    rename table(:messages), :channel_id, to: :thread_id
  end

  def down do
    rename table(:messages), :thread_id, to: :channel_id
  end
end
