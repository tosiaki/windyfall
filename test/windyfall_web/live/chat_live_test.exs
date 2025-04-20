defmodule WindyfallWeb.ChatLiveTest do
  use WindyfallWeb.ConnCase, async: true # async: true is usually fine

  import Phoenix.LiveViewTest
  import Windyfall.Factory # Assuming you have or will create test data factories
  import Plug.Conn
  import Phoenix.PubSub, only: [subscribe: 2]

  alias Windyfall.Messages
  alias Windyfall.Accounts
  alias WindyfallWeb.ChatLive
  alias WindyfallWeb.UserAuth
  alias Ecto.Adapters.SQL.Sandbox
  alias Windyfall.PubSubTopics
  alias Phoenix.Socket.Broadcast

  @session_options [
    store: :cookie,
    key: "_windyfall_key", # Must match endpoint config
    signing_salt: "RVZhZAZq", # Must match endpoint config
    # encryption_salt: ... # Add if endpoint uses encryption
    same_site: "Lax"
  ]

  # Creates a user and adds it to the context as :user
  defp setup_user(_context) do
    user = insert(:user) # Using the factory now
    {:ok, user: user} # MUST return :ok tuple or map to merge
  end

  # Creates a conn, logs in the user from context, adds conn to context
  defp setup_conn(context) do # NEEDS context to get :user
    user = context.user # Get user added by setup_user
    token = Accounts.generate_user_session_token(user) 

    session_config = Plug.Session.init(@session_options)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Session.call(session_config)
      |> fetch_session()
      |> Plug.Conn.put_session(:user_token, token)
      |> Plug.Conn.put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")

    {:ok, conn: conn} # Add conn to the context
  end

  # Sets up specific chat data, using user/conn from context
  defp setup_basic_chat_data(context) do
    user1 = context.user # Get user from context
    # conn = context.conn # Get conn if needed

    # Create other data using user1
    user2 = insert(:user)
    game_topic = insert(:topic, name: "Game Chat", path: "game")
    initial_game_thread = insert_thread_with_first_message!(%{
      topic: game_topic,
      creator: user1,
      title: "General Game Chat",
      first_message: "First message!"
    })
    msg2 = insert(:message, thread_id: initial_game_thread.id, user_id: user2.id, message: "Second message")

    reloaded_game_thread = Windyfall.Repo.get!(Messages.Thread, initial_game_thread.id)
    preloaded_game_thread = Windyfall.Repo.preload(reloaded_game_thread, [messages: [:user], creator: []])

    preloaded_msg2 = Enum.find(preloaded_game_thread.messages, &(&1.id == msg2.id))
    refute is_nil(preloaded_msg2), "msg2 was not found in preloaded game_thread.messages" # Add assertion

    # Return map to merge into context for the test
    %{
      user1: user1, # Keep user1 accessible if tests need it directly
      user2: user2,
      game_topic: game_topic,
      game_thread: preloaded_game_thread,
      msg2: preloaded_msg2
    }
    # No need for {:ok, ...} here if just returning a map
  end

  defp mount_view(conn, path) do
    cache_pid = Process.whereis(Windyfall.ReactionCache)
    refute is_nil(cache_pid), "ReactionCache GenServer not started"
    Sandbox.allow(Windyfall.Repo, self(), cache_pid)
    live(conn, path)
  end

  def insert_thread_with_first_message!(attrs \\ %{}) when is_map(attrs) do
    # Use the non-bang version internally, raise if it returns error
    case insert_thread_with_first_message(attrs) do
      {:ok, thread} -> thread
      {:error, reason} -> raise "Failed to insert thread with first message: #{inspect(reason)}"
    end
  end

  # --- Start Test Descriptions ---

  describe "Mounting and Initial Render" do
    # --- Correct Setup Call ---
    # Call the setup functions sequentially. Context is passed along.
    setup [:setup_user, :setup_conn, :setup_basic_chat_data]

    # The test context map (%{conn: ..., user: ..., game_topic: ..., ...})
    # is automatically passed as the argument here.
    test "mounts correctly when navigating to a topic thread", %{conn: conn, game_topic: t, game_thread: th, user: logged_in_user} do
      {:ok, view, _html} = mount_view(conn, ~p"/t/#{t.path}/thread/#{th.id}")

      assert has_element?(view, "#messages")
      assert has_element?(view, "#message-input")
      # Ensure messages are loaded correctly before accessing them
      first_message_id = th.messages |> List.first() |> Map.get(:id)
      last_message_id = th.messages |> List.last() |> Map.get(:id)
      refute is_nil(first_message_id) # Add checks
      refute is_nil(last_message_id)
      assert has_element?(view, "#message-#{first_message_id}")
      assert has_element?(view, "#message-#{last_message_id}")
      assert render(view) =~ t.name
    end

    # Update other tests similarly to use the context correctly
    test "mounts correctly when navigating directly to a user's thread", %{conn: conn, user: u1} do # user1 comes from setup_user
      u1_thread = insert_thread_with_first_message!(%{
          context_type: :user, # Specify user context
          user: u1,         # The user whose context it is
          creator: u1,      # The user creating it
          title: "User1 Thread",
          first_message: "My own message"
      })

       {:ok, view, html} = mount_view(conn, ~p"/u/#{u1.handle}/thread/#{u1_thread.id}")

       # Find the heading element and check its decoded text content
       # Adjust the selector '.text-xl' if your heading class/tag is different
       assert Floki.find(html, ".text-xl") |> Floki.text() =~ "#{u1.display_name}'s Profile"

       # Check for the message ID
       first_msg_id = u1_thread.messages |> List.first() |> Map.get(:id)
       refute is_nil(first_msg_id)
       assert has_element?(view, "#message-#{first_msg_id}")

       # Test with ID
       path_id = ~p"/uid/#{u1.id}/thread/#{u1_thread.id}"
       {:ok, view_id, html_id} = live(conn, path_id)

       # Use Floki again
       assert Floki.find(html_id, ".text-xl") |> Floki.text() =~ "#{u1.display_name}'s Profile"
       # Check for the message ID
       assert has_element?(view_id, "#message-#{first_msg_id}")
    end

     test "loads older messages via hook event", %{conn: conn, game_topic: t, game_thread: th, user: c} do # creator comes from setup_user
        # Create more messages
        Enum.each(1..55, fn i ->
           insert(:message, thread_id: th.id, user_id: c.id, message: "Older message #{i}")
        end)

        {:ok, view, html} = mount_view(conn, ~p"/t/#{t.path}/thread/#{th.id}")

        message_content_selector = "#messages .prose" 

        assert has_element?(view, message_content_selector, "Older message 6")
        refute has_element?(view, message_content_selector, "Second message")
      # refute has_element?(view, message_content_selector, "Older message 5")

        # Assert that the LiveView knows it's NOT at the beginning of the history
        # --- Simulate the Hook sending the event ---
        # Target the element the hook is attached to (#messages) and send the event
        # The third argument is the payload (empty map {} in this case)
        rendered_after_load = render_hook(view, "load-before", %{})
     
        # --- Assert the results ---
        # Check that the previously invisible older message is now rendered
        assert rendered_after_load =~ "Older message 1"
        assert rendered_after_load =~ "Older message 5"
        # Check that the original messages are still there
        assert rendered_after_load =~ "First message!"
        assert rendered_after_load =~ "Second message"
        # Check that the messages loaded between the initial set and the oldest are there
        assert rendered_after_load =~ "Older message 6" # Still present
        # Optional (more brittle): Assert initial message count if needed
        # initial_load_count = 50 # Based on hardcoded limit in messages_before
        # assert length(view.assigns.messages) > 0 # Ensure some messages loaded
        # assert Enum.sum(Enum.map(view.assigns.messages, &length(&1.messages))) == initial_load_count
     end
  end

  describe "Sending Messages" do
    setup [:setup_user, :setup_conn, :setup_basic_chat_data]

    test "sends a new text message", %{conn: conn, game_topic: t, game_thread: th, user: u1} do
      {:ok, view, _html} = mount_view(conn, ~p"/t/#{t.path}/thread/#{th.id}")
      thread_topic = PubSubTopics.thread(th.id)

      # Subscribe test process to thread topic to check broadcast
      subscribe(Windyfall.PubSub, thread_topic)

      user_id = u1.id

      form_selector = "#message-input-form" # Use the ID from MessageInputComponent
      message_text = "Hello from test!"

      form_element = element(view, form_selector)
      # Simulate submitting the form
      render_submit(form_element, %{"new_message" => message_text})

      # Assert broadcast was sent
      assert_receive %Broadcast{event: "new_message", payload: %{message: ^message_text, user_id: ^user_id}, topic: ^thread_topic}

      # Assert message appears in the UI (might take a moment due to broadcast)
      # We check the raw render output *after* the submit triggers the broadcast/handle_info
      # Wait slightly for broadcast processing if needed: Process.sleep(50)
      assert render(view) =~ message_text

      # Assert input clear event was pushed (optional, tests JS interaction)
      # assert_push view, "sent-message", %{}
    end

    @tag :reply_message
    test "sends a reply message", %{conn: conn, game_topic: t, game_thread: th, user: u1, msg2: msg_to_reply_to} do
       {:ok, view, _html} = mount_view(conn, ~p"/t/#{t.path}/thread/#{th.id}")

       refute is_nil(msg_to_reply_to.user), "User should be preloaded on msg_to_reply_to" # Add assertion

       thread_topic = PubSubTopics.thread(th.id)
       subscribe(Windyfall.PubSub, thread_topic)

       user_id = u1.id
       reply_target_id = msg_to_reply_to.id
       reply_target_user_name = msg_to_reply_to.user.display_name

       # --- Simulate clicking the 'Reply' action ---
       # Send the internal message that handle_event("context_menu_action", ...) would send
       send(view.pid, {:start_reply, msg_to_reply_to.id})
       rendered_after_reply_start = render(view)

       assert rendered_after_reply_start =~ "Replying to #{msg_to_reply_to.user.display_name}"
       assert has_element?(view, ".reply-indicator")

       # Assert reply indicator is visible
      # assert has_element?(rendered_after_reply_start, ".reply-indicator", ~r/Replying to #{msg_to_reply_to.user.display_name}/)
      
       # Send the reply
       form_selector = "#message-input-form"
       reply_text = "This is a reply"
       form_element = element(view, form_selector) # Find the form element
       render_submit(form_element, %{"new_message" => reply_text})

       # Assert broadcast includes reply info
       assert_receive %Broadcast{
         event: "new_message",
         payload: %{
           message: ^reply_text,
           user_id: ^user_id,
           replying_to_message_id: ^reply_target_id,
           replying_to: %{id: ^reply_target_id}
         },
         topic: ^thread_topic
       }

       # Assert reply UI renders (check for reply context block)
       # Wait slightly for broadcast processing if needed: Process.sleep(50)
       assert render(view) =~ reply_text
       refute has_element?(view, ".reply-indicator"), "Expected reply indicator near input to be removed"
    end

    # Test for sending attachments would be more complex, requiring
    # simulating the upload lifecycle (`allow_upload`, `render_upload`, `consume_uploaded_entries`)
    # Skipping for now to focus on core functionality tested by existing tests.
  end

  describe "Reactions" do
      setup [:setup_user, :setup_conn, :setup_basic_chat_data]

      @tag :reactions
      test "adds and removes a reaction", %{conn: conn, game_topic: t, game_thread: th, user: u1} do
          {:ok, view, _html} = mount_view(conn, ~p"/t/#{t.path}/thread/#{th.id}")
          first_message = case th.messages do
                            [] -> insert(:message, thread_id: th.id, user_id: u1.id, message: "Reaction test msg") |> Windyfall.Repo.preload(:user)
                            [msg | _] -> msg
                          end
          refute is_nil(first_message), "Could not get first message for reaction test"

          emoji = "👍"
          reaction_picker_button_selector = "#message-#{first_message.id} .reaction-picker .reaction-item button[phx-value-emoji=\"#{emoji}\"]"
          # Selector for the button's count display
          reaction_badge_selector = "#reactions-#{first_message.id} button.reaction[phx-value-emoji=\"#{emoji}\"]"
          reaction_badge_count_selector = reaction_badge_selector <> " .count"
          # Selector checking reacted state on the BADGE
          reacted_badge_selector = reaction_badge_selector <> "[data-user-reacted=\"true\"]"
        
          # --- Initial state assertion ---
          # Check if the button exists but doesn't show count 1 and isn't marked reacted
          # It might start hidden if count is 0, so we check for absence of reacted state primarily
          refute has_element?(view, reacted_badge_selector)

          # --- 1. Add reaction ---
          # Find the specific button element
          reaction_picker_button_element = element(view, reaction_picker_button_selector)
          # Click the specific button element
          render_click(reaction_picker_button_element)

          # Assert UI update after delay
          Process.sleep(50) # Small delay
          assert has_element?(view, reaction_badge_selector) # Badge should exist
          assert has_element?(view, reaction_badge_count_selector, "1") # Count on badge
          assert has_element?(view, reacted_badge_selector) # Badge marked as reacted

          # --- 2. Remove reaction ---
          # Find the element again (state might have changed)
          reaction_picker_button_element_to_remove = element(view, reaction_picker_button_selector)
          # Click the specific button element again
          render_click(reaction_picker_button_element_to_remove)

          # Assert UI update after delay
          Process.sleep(50)
          # Check either count is 0 OR element is hidden (data-count="0" has @apply hidden)
          # AND check that data-user-reacted is false
          refute has_element?(view, reaction_badge_selector), "Expected reaction badge for '#{emoji}' to be removed from DOM"
      end
  end

  describe "Editing and Deleting Messages" do
     setup [:setup_user, :setup_conn, :setup_basic_chat_data]

     @tag :edit
     test "edits own message", %{conn: conn, game_topic: t, game_thread: th, user: u1} do
        # Make sure u1 created the message we want to edit
        msg_to_edit = th.messages |> Enum.find(&(&1.user_id == u1.id))
        refute is_nil(msg_to_edit), "Setup error: Logged in user didn't create a message"
        original_text = msg_to_edit.message
        edited_text = "This message has been edited."
        thread_topic = PubSubTopics.thread(th.id)

        {:ok, view, _html} = mount_view(conn, ~p"/t/#{t.path}/thread/#{th.id}")
        subscribe(Windyfall.PubSub, thread_topic)

        message_id_to_edit = msg_to_edit.id

        send(view.pid, {:start_edit, message_id_to_edit})
        rendered_after_edit_start = render(view)

        # Assert edit form appears
        edit_form_selector = "#edit-form-#{msg_to_edit.id}"
        assert rendered_after_edit_start =~ "slate-editor-edit-#{msg_to_edit.id}"
        # Assert original text is not directly visible in normal prose view
        refute rendered_after_edit_start =~ ~r"<div class=\"prose.*?#{Regex.escape(original_text)}.*?</div>"

        # Simulate saving the edit (submit the inner form)
        edit_form_element = element(view, edit_form_selector)
        render_submit(edit_form_element, %{"content" => edited_text})

        # Assert broadcast
        assert_receive %Broadcast{event: "message_updated", payload: %{id: ^message_id_to_edit, message: ^edited_text}, topic: ^thread_topic}

        # Assert UI updates: form gone, edited text shown
        # Wait for broadcast processing
        Process.sleep(50)
        final_html = render(view)
        refute final_html =~ edit_form_selector # Form should be gone
        assert has_element?(view, "#message-#{msg_to_edit.id} .prose", edited_text)
     end

     @tag :delete_own
     test "deletes own message", %{conn: conn, game_topic: t, game_thread: th, user: u1} do
        msg_to_delete = th.messages |> Enum.find(&(&1.user_id == u1.id))
        refute is_nil(msg_to_delete), "Setup error: Logged in user didn't create a message"
        message_selector = "#message-#{msg_to_delete.id}"
        thread_topic = PubSubTopics.thread(th.id)

        {:ok, view, _html} = mount_view(conn, ~p"/t/#{t.path}/thread/#{th.id}")
        subscribe(Windyfall.PubSub, thread_topic)

        message_id_to_delete = msg_to_delete.id

        assert has_element?(view, message_selector) # Verify message exists initially

        # --- Simulate deletion via send/2 ---
        send(view.pid, {:delete_message, message_id_to_delete})
        # Assert broadcast
        assert_receive %Broadcast{event: "message_deleted", payload: %{id: ^message_id_to_delete}, topic: ^thread_topic}

        # Assert UI update: message is gone
        Process.sleep(50) # Wait for broadcast
        refute has_element?(view, message_selector)
     end

      @tag :delete_other
      test "handle_info prevents deleting other user's message", %{conn: conn, game_topic: t, game_thread: th, user: u1, msg2: other_user_msg} do
        message_id_other = other_user_msg.id
        message_selector = "#message-#{message_id_other}"
        thread_topic = PubSubTopics.thread(th.id)

        {:ok, view, _html} = mount_view(conn, ~p"/t/#{t.path}/thread/#{th.id}")
        subscribe(Windyfall.PubSub, thread_topic)

        assert has_element?(view, message_selector) # Verify message exists

        # --- Simulate clicking the 'Delete' action ---
        send(view.pid, {:delete_message, other_user_msg.id})

        # Assert NO broadcast was sent
        refute_receive %Broadcast{event: "message_deleted"}, 10

        # Assert message is still present
        final_html = render(view)
        assert final_html =~ other_user_msg.message # Check content still there
        # Or check element presence again
        Process.sleep(10)
        assert has_element?(view, message_selector)

        # Assert flash message indicates error
        # assert has_element?(view, ".alert-danger", "You cannot delete this message.") # Check CoreComponents flash selector/text
        # TODO: Find a reliable way to test flash messages set in handle_info/event if needed later.
      end
  end

  # --- Placeholder for next steps ---
  # describe "Sending Messages" do
  #   setup [:user, :conn, :setup_basic_chat_data]
  #   test "user can send a message", %{conn: conn, game_topic: topic, game_thread: thread, user: current_user} do
  #     # ...
  #   end
  # end

  # describe "Loading Older Messages" do
  #   # ...
  # end

  # describe "Reactions" do
  #   # ...
  # end

  # ... etc for other features ...

end
