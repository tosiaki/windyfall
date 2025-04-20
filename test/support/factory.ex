defmodule Windyfall.Factory do
  use ExMachina.Ecto, repo: Windyfall.Repo # Use ExMachina.Ecto

  alias Windyfall.Accounts.User
  alias Windyfall.Messages.{Topic, Thread, Message, Attachment, Reaction} # Add other schemas as needed

  # --- User Factory ---
  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      handle: sequence(:handle, &"userhandle#{&1}"),
      display_name: sequence(:display_name, &"Test User #{&1}"),
      hashed_password: Pbkdf2.hash_pwd_salt("password1234"), # Hash a default password
      confirmed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      # profile_image: "/images/default-avatar.png" # Optional default
    }
  end

  # --- Topic Factory ---
  def topic_factory do
    %Topic{
      name: sequence(:topic_name, &"Topic Name #{&1}"),
      path: sequence(:topic_path, &"topic-path-#{&1}")
    }
  end

  # --- Thread Factory ---
  # Requires creator_id and either topic_id OR user_id (for context)
  def thread_factory do
    # Default to a topic context if not specified
    topic = build(:topic) # Build (don't insert yet) a topic dependency
    creator = build(:user) # Build a user dependency

    %Thread{
      title: sequence(:thread_title, &"Thread Title #{&1}"),
      # We need to insert dependencies before associating by ID
      # Associations can handle this better:
      creator: creator,
      topic: topic, # Default to topic context
      user: nil # Explicitly nil for user context unless overridden
    }
  end

  # --- Message Factory ---
  # Requires thread_id and user_id
  def message_factory do
    # Build dependencies
    # thread = build(:thread) # Careful with nested builds, might insert multiple users/topics
    # user = build(:user)

    %Message{
      message: sequence(:message_text, &"This is message content number #{&1}."),
      # Associate using structs (ExMachina handles inserting if needed)
      # thread: thread, # Associate like this OR pass IDs when inserting
      # user: user
      replying_to: nil # Default to no reply
    }
  end

  # --- Attachment Factory ---
  def attachment_factory do
    # Requires message_id
    # message = build(:message)

    %Attachment{
      filename: sequence(:filename, &"file_#{&1}.txt"),
      web_path: sequence(:web_path, &"/uploads/test/file_#{&1}.txt"),
      content_type: "text/plain",
      size: sequence(:size, &(&1 * 100 + 50)),
      # message: message
    }
  end

   # --- Reaction Factory ---
   def reaction_factory do
     %{
       emoji: Enum.random(["👍", "❤️", "😂", "🤔"]),
       # user: build(:user),
       # message: build(:message)
     }
   end

  # Helper to insert a thread with its first message atomically
  # (Similar to context function but for tests)
  def insert_thread_with_first_message(attrs \\ %{}) when is_map(attrs) do
    # ... (determine creator, context_type, context_id) ...
    creator = Map.get(attrs, :creator) || insert(:user)
    context_type = Map.get(attrs, :context_type, :topic)
    {context_key, context_obj} = # ... determine context obj ...
       case context_type do
         :topic -> {:topic, Map.get(attrs, :topic, insert(:topic))}
         :user  -> {:user, Map.get(attrs, :user, insert(:user))}
       end
    context_id = context_obj.id

    thread_cast_attrs = %{creator_id: creator.id} # ... merge other attrs ...
      |> Map.merge(Map.take(attrs, [:title, :spin_off_of_message_id]))

    thread_changeset = Thread.changeset(%Thread{}, thread_cast_attrs, context_type, context_id)

    # Use a with statement for cleaner error propagation
    with {:ok, inserted_thread} <- Windyfall.Repo.insert(thread_changeset),
         # Proceed only if thread insertion succeeds
         message_text = Map.get(attrs, :first_message, "Default message..."),
         message_changeset = Message.changeset(%Message{}, %{message: message_text, thread_id: inserted_thread.id, user_id: creator.id}),
         {:ok, _inserted_message} <- Windyfall.Repo.insert(message_changeset)
         # Proceed only if message insertion succeeds
    do
      # Preload associations on the successfully inserted thread
      preloaded_thread = Windyfall.Repo.preload(inserted_thread, [:messages, :creator, :topic, :user])
      # --- Return the OK tuple ---
      {:ok, preloaded_thread}
    else
      # Handle errors from either Repo.insert call
      {:error, changeset} ->
        # You might want to differentiate between thread/message changeset errors
        {:error, changeset} # Propagate the error changeset

      # Handle any other unexpected error patterns from `with` if necessary
      error ->
        {:error, error} # Propagate unknown error
    end
  end

end
