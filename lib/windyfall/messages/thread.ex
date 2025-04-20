defmodule Windyfall.Messages.Thread do
  use Ecto.Schema
  import Ecto.Changeset

  schema "threads" do
    field :title, :string
    field :message_count, :integer, default: 0
    field :last_message_at, :naive_datetime
    field :spin_off_of_message_id, :id

    # --- Context Fields (Mutually Exclusive) ---
    belongs_to :topic, Windyfall.Messages.Topic, foreign_key: :topic_id
    belongs_to :user, Windyfall.Accounts.User, foreign_key: :user_id

    # --- Creator Field ---
    belongs_to :creator, Windyfall.Accounts.User, foreign_key: :creator_id

    has_many :messages, Windyfall.Messages.Message

    timestamps()
  end

  def changeset(thread, attrs, context_type \\ nil, context_id \\ nil) do
    thread
    |> cast(attrs, [:title, :spin_off_of_message_id, :creator_id]) # Remove topic_id/user_id from initial cast
    |> validate_required([:title, :creator_id])
    |> validate_length(:title, min: 3, max: 100)
    # Apply context changes *before* validating context presence
    |> maybe_put_context(context_type, context_id)
    |> validate_exactly_one_context() # Now validate context presence
  end

  # Helper to add context changes
  defp maybe_put_context(changeset, context_type, context_id) do
     case context_type do
       :topic ->
          changeset
          |> put_change(:topic_id, context_id)
          |> put_change(:user_id, nil) # Ensure exclusivity
       :user ->
          changeset
          |> put_change(:user_id, context_id)
          |> put_change(:topic_id, nil) # Ensure exclusivity
       _ ->
          # If no context provided, don't add changes yet
          # validate_exactly_one_context will catch this later
          changeset
     end
  end

  defp validate_exactly_one_context(changeset) do
    topic_id = get_field(changeset, :topic_id)
    user_id = get_field(changeset, :user_id)

    cond do
      !is_nil(topic_id) and !is_nil(user_id) ->
        add_error(changeset, :base, "Thread target cannot be both a topic and a user")
      is_nil(topic_id) and is_nil(user_id) ->
        IO.inspect changeset, label: "the changeset for context validation"
        add_error(changeset, :base, "Thread must have a target topic or user")
      true ->
        changeset
    end
  end
end
