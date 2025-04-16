defmodule Windyfall.Messages.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :message, :string
    
    belongs_to :thread, Windyfall.Messages.Thread
    belongs_to :user, Windyfall.Accounts.User
    has_many :reactions, Windyfall.Messages.Reaction, on_delete: :delete_all
    belongs_to :replying_to, __MODULE__, foreign_key: :replying_to_message_id

    timestamps()
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:message, :thread_id, :user_id, :replying_to_message_id])
    |> validate_required([:message, :thread_id, :user_id])
    |> validate_required([:message], message: "Message cannot be empty")
    |> validate_length(:message, min: 1, max: 10000)
    # Optional: Validate that replying_to_message_id exists and belongs to the same thread_id
    # This requires fetching the parent message inside the validation, which can be complex.
    # อาจจะทำใน context function แทนได้
  end
end
