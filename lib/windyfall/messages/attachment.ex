defmodule Windyfall.Messages.Attachment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  # If messages.id is still integer, keep @foreign_key_type :id

  schema "attachments" do
    field :filename, :string
    field :web_path, :string
    field :content_type, :string
    field :size, :integer

    belongs_to :message, Windyfall.Messages.Message # Foreign key type deduced if set above

    timestamps()
  end

  @doc false
  def changeset(attachment, attrs) do
    attachment
    # Use cast/validate as needed, most fields set programmatically during upload
    |> cast(attrs, [:filename, :web_path, :content_type, :size, :message_id])
    |> validate_required([:filename, :web_path, :size, :message_id])
  end
end
