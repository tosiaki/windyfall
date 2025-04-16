defmodule Windyfall.Messages.Share do
  use Ecto.Schema
  import Ecto.Changeset

  schema "shares" do
    # No longer need target_context_type/identifier

    belongs_to :user, Windyfall.Accounts.User, foreign_key: :user_id # Sharer
    belongs_to :thread, Windyfall.Messages.Thread # Shared thread

    # Specific target associations
    belongs_to :target_topic, Windyfall.Messages.Topic, foreign_key: :target_topic_id
    belongs_to :target_user, Windyfall.Accounts.User, foreign_key: :target_user_id

    timestamps()
  end

  @doc false
  def changeset(share, attrs) do
    share
    |> cast(attrs, [
         :user_id,
         :thread_id,
         :target_topic_id,
         :target_user_id
       ])
    |> validate_required([
         :user_id,
         :thread_id
         # Target IDs are not required together, validated by custom rule/DB constraint
       ])
    |> validate_exactly_one_target() # Add custom validation
  end

  # Custom validation to ensure one and only one target FK is set
  defp validate_exactly_one_target(changeset) do
     topic_id = get_field(changeset, :target_topic_id)
     user_id = get_field(changeset, :target_user_id)

     cond do
       # Both are set
       !is_nil(topic_id) and !is_nil(user_id) ->
         add_error(changeset, :base, "Share target cannot be both a topic and a user")
       # Neither are set
       is_nil(topic_id) and is_nil(user_id) ->
         add_error(changeset, :base, "Share must have a target topic or user")
       # Exactly one is set (valid case)
       true ->
         changeset
     end
  end
end
