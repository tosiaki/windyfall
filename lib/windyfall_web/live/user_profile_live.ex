defmodule WindyfallWeb.UserProfileLive do
  use WindyfallWeb, :live_view

  alias Windyfall.Accounts

  def render(assigns) do
    ~H"""
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

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    profile_changeset = Accounts.change_user_profile(user)

    socket =
      socket
      |> assign(:current_display_name, user.display_name)
      |> assign(:current_handle, user.handle)
      |> assign(:current_profile_image, user.profile_image)
      |> assign(:trigger_submit, false)
      |> assign(:profile_form, to_form(profile_changeset))
      |> allow_upload(:profile_image,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 1,
        max_file_size: 50_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  def handle_event("update_profile", params, socket) do
    user = socket.assigns.current_user
    user_params = params["user"]
    user_params = Map.put(user_params, "profile_image", socket.assigns.profile_image)

    case Accounts.update_user_profile(user, user_params) do
      {:ok, user} ->
        profile_form =
          user
          |> Accounts.change_user_profile(user_params)
          |> to_form()

        socket = assign(socket,
          trigger_submit: true,
          profile_form: profile_form,
          current_display_name: user_params["display_name"],
          current_handle: user_params["handle"])

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, profile_form: to_form(changeset))}
    end
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
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
end


