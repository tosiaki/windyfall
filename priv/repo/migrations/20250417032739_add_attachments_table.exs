defmodule Windyfall.Repo.Migrations.AddAttachmentsTable do
  use Ecto.Migration

  def change do
    create table(:attachments, primary_key: false) do
      add :id, :uuid, primary_key: true # Use UUID for primary key
      add :filename, :string, null: false # Original filename
      add :web_path, :string, null: false # Path relative to static root (e.g., "/uploads/messages/...")
      add :content_type, :string # MIME type
      add :size, :integer # Size in bytes
      add :message_id, references(:messages, on_delete: :delete_all, type: :id), null: false # Link to message

      timestamps()
    end

    create index(:attachments, [:message_id])
  end
end
