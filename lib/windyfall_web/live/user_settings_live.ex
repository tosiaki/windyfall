defmodule WindyfallWeb.UserSettingsLive do
  use WindyfallWeb, :live_view

  alias Windyfall.Accounts

  def render(assigns) do
    ~H"""
    <.header class="text-center">
      Account Settings
      <:subtitle>Manage your account email address and password settings</:subtitle>
    </.header>

    <div class="space-y-12 divide-y">
      <div>
        <.simple_form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <.input field={@email_form[:email]} type="email" label="Email" required />
          <.input
            field={@email_form[:current_password]}
            name="current_password"
            id="current_password_for_email"
            type="password"
            label="Current password"
            value={@email_form_current_password}
            required
          />
          <:actions>
            <.button phx-disable-with="Changing...">Change Email</.button>
          </:actions>
        </.simple_form>
      </div>
      <div>
        <.simple_form
          for={@password_form}
          id="password_form"
          action={~p"/users/log_in?_action=password_updated"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            field={@password_form[:email]}
            type="hidden"
            id="hidden_user_email"
            value={@current_email}
          />
          <.input field={@password_form[:password]} type="password" label="New password" required />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password"
          />
          <.input
            field={@password_form[:current_password]}
            name="current_password"
            type="password"
            label="Current password"
            id="current_password_for_password"
            value={@current_password}
            required
          />
          <:actions>
            <.button phx-disable-with="Changing...">Change Password</.button>
          </:actions>
        </.simple_form>
      </div>
    </div>

    <.header class="text-center">
      Account Profile
      <:subtitle>Manage your account profile</:subtitle>
    </.header>

    <div class="space-y-12 divide-y">
      <div>
        <.simple_form
          for={@profile_form}
          id="profile_form"
          phx-submit="update_profile"
          phx-change="validate"
        >
          <.input
            field={@profile_form[:display_name]}
            value={@current_display_name}
            label="Display name"
          />
          <.input
            field={@profile_form[:handle]}
            value={@current_handle}
            label="Handle"
          />
          <.live_file_input upload={@uploads.profile_image}/>
          <figure class="max-w-36">
              <div>Profile image</div>
              <img src={@current_profile_image} />
          </figure>
          <%= for entry <- @uploads.profile_image.entries do %>
            <progress value={entry.progress} max="100"><%= entry.progress %>%</progress>
          <% end %>
          <:actions>
            <.button phx-disable-with="Changing...">Change Profile</.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok ->
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)
    profile_changeset = Accounts.change_user_profile(user)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:current_display_name, user.display_name)
      |> assign(:current_handle, user.handle)
      # Assign CURRENT image path initially
      |> assign(:current_profile_image, user.profile_image)
      # Track if a new image is staged for saving
      |> assign(:staged_profile_image, nil)
      |> assign(:trigger_submit, false)
      |> assign(:profile_form, to_form(profile_changeset))
      |> allow_upload(:profile_image,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 1,
        max_file_size: 50_000_000,
        auto_upload: true
      )

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  def handle_event("update_profile", %{"user" => user_params}, socket) do
    user = socket.assigns.current_user
    uploaded_path = consume_uploaded_image(socket) # New helper

    # Prepare params, only adding profile_image if it was uploaded
    params_to_save =
      if uploaded_path do
        Map.put(user_params, "profile_image", uploaded_path)
      else
        # If no new image, *exclude* profile_image from the params sent to update_user_profile
        # This prevents accidentally overwriting the existing image with nil or empty string.
        Map.drop(user_params, ["profile_image"])
      end

    case Accounts.update_user_profile(user, params_to_save) do
      {:ok, updated_user} ->
        # Update assigns to reflect saved state
        profile_form = Accounts.change_user_profile(updated_user) |> to_form()
        socket =
          socket
          |> assign(profile_form: profile_form)
          |> assign(:current_display_name, updated_user.display_name)
          |> assign(:current_handle, updated_user.handle)
          |> assign(:current_profile_image, updated_user.profile_image)
          |> assign(:staged_profile_image, nil)
          |> put_flash(:info, "Profile updated successfully.")

        {:noreply, socket}

      {:error, changeset} ->
        # If save fails, potentially keep staged image path for re-render?
        # Or clear it? Clearing might be safer.
        {:noreply,
          socket
          |> assign(:profile_form, to_form(changeset))
          # |> assign(:staged_profile_image, nil) # Optional: clear staged image on error
        }
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_profile(socket.assigns.current_user, user_params)
    {:noreply, assign(socket, profile_form: to_form(Map.put(changeset, :action, :validate)))}
  end

  defp handle_progress(:profile_image, entry, socket) do
    if entry.done? do
      path =
        consume_uploaded_entry(
          socket,
          entry,
          fn %{path: path} ->
            dest = Path.join("priv/static/images", Path.basename(path))
            File.cp!(path, dest)
            {:ok, ~p"/images/#{Path.basename(dest)}"}
          end
        )
      {:noreply,
        socket
        |> put_flash(:info, "file #{entry.client_name} uploaded")
        |> assign(:profile_image, path)}
    else
      {:noreply, socket}
    end
  end

  defp consume_uploaded_image(socket) do
    # Get the configured relative path
    upload_dir_config = Application.fetch_env!(:windyfall, WindyfallWeb.Endpoint)[:static_uploads]
    # Get the absolute path to the project's static upload directory
    # Path.expand converts the relative config path based on the current working dir (project root)
    dest_dir_abs = Path.expand(upload_dir_config)

    results =
      consume_uploaded_entries(socket, :profile_image, fn %{path: temp_path}, _entry ->
        # path: The temporary path where the upload was stored by Phoenix
        # _entry: Contains metadata about the upload

        original_filename = Path.basename(temp_path) # Use basename from temp path
        safe_filename = "#{Ecto.UUID.generate()}-#{original_filename}"
        dest_path_abs = Path.join(dest_dir_abs, safe_filename) # Save to absolute path

        # Ensure the destination directory exists
        File.mkdir_p!(dest_dir_abs)

        # Copy the file from the temporary location to the final destination
        case File.cp(temp_path, dest_path_abs) do
           :ok ->
             # Return the web-accessible path (relative to the static root)
             # No leading slash needed if Plug.Static serves from priv/static at "/"
             web_path = "/uploads/#{safe_filename}"
             {:ok, web_path} # MUST return {:ok, result} for consume_uploaded_entries
           {:error, reason} ->
             # Log error, return an error tuple for consume_uploaded_entries
             Logger.error("Failed to copy uploaded file: #{reason}")
             {:error, reason}
        end
      end)

    # consume_uploaded_entries returns a list of the results from the callback
    # We expect [{:ok, web_path}] or [{:error, reason}] or []
    case results do
      [{:ok, web_path} | _] -> web_path # Extract the path on success
      _ -> nil                         # Handle empty list or error case
    end
  end
end
