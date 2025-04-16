defmodule Windyfall.Repo.Migrations.AddReplyToMessageIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      # Add the column, allowing NULL values (not all messages are replies)
      # Add a foreign key constraint referencing the same table
      # on_delete: :nilify means if the replied-to message is deleted,
      # the reply_to link becomes NULL (the reply message still exists).
      # Choose :delete_all if replies should be deleted when the parent is.
      add :replying_to_message_id, references(:messages, on_delete: :nilify_all), null: true
    end

    # Add an index for potentially faster lookups of replies or parents
    create index(:messages, [:replying_to_message_id])
  end
end
