defmodule Windyfall.Messages.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :message, :string
    
    belongs_to :thread, Windyfall.Messages.Thread
    belongs_to :user, Windyfall.Accounts.User
    has_many :reactions, Windyfall.Messages.Reaction, on_delete: :delete_all
    belongs_to :replying_to, __MODULE__, foreign_key: :replying_to_message_id
    has_many :attachments, Windyfall.Messages.Attachment, on_delete: :delete_all

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:message, :thread_id, :user_id, :replying_to_message_id])
    |> validate_required([:thread_id, :user_id])
    |> validate_message_or_attachment()
    |> validate_length(:message, max: 10000)
    # Optional: Validate that replying_to_message_id exists and belongs to the same thread_id
    # This requires fetching the parent message inside the validation, which can be complex.
    # อาจจะทำใน context function แทนได้
  end

  # Custom validation: Require message OR attachments (will be added later)
  defp validate_message_or_attachment(changeset) do
    # We'll enhance this validation later when handling attachments in the context
    message = get_field(changeset, :message)
    # attachments = get_field(changeset, :attachments_metadata) # Placeholder

    # For now, allow empty message text during creation via context
    # The real check will happen in the context function before inserting.
    if message == nil or String.trim(message) == "" do
       changeset # Allow empty for now
    else
       validate_length(changeset, :message, min: 1) # Apply min length only if message exists
    end
  end
end
