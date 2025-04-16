defmodule WindyfallWeb.Router do
  use WindyfallWeb, :router

  import WindyfallWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WindyfallWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WindyfallWeb do
    pipe_through :browser

    get "/", PageController, :home

    live_session :chat,
      on_mount: [{WindyfallWeb.UserAuth, :mount_current_user}] do
      live "/chat", ChatLive, :index
      live "/chat/thread/:thread_id", ChatLive, :thread

      # Topic routes
      live "/t/:topic_path", ChatLive, :topic
      live "/t/:topic_path/thread/:thread_id", ChatLive, :topic_thread

      # User Routes (Handle & ID)
      live "/u/:user_handle", ChatLive, :user
      live "/uid/:user_id", ChatLive, :user_id
      live "/u/:user_handle/thread/:thread_id", ChatLive, :user_thread
      live "/uid/:user_id/thread/:thread_id", ChatLive, :user_id_thread
    end
  end

  scope "/", WindyfallWeb do
    pipe_through [:browser, Windyfall.GameSession]
    live "/game", GameLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", WindyfallWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:windyfall, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WindyfallWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", WindyfallWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{WindyfallWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", WindyfallWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{WindyfallWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
      live "/users/profile", UserProfileLive, :edit
    end
  end

  scope "/", WindyfallWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{WindyfallWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  defp assign_streams(conn, _opts) do
    Phoenix.LiveView.Controller.live_render(conn, MyAppWeb.PageLive, session: %{"streams" => %{}})
  end
end
