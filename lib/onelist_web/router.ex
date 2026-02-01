defmodule OnelistWeb.Router do
  use OnelistWeb, :router

  import Phoenix.LiveView.Router

  # Define the authentication plugs
  defp require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:error, "You must be logged in to access this page.")
      |> Phoenix.Controller.redirect(to: "/login")
      |> halt()
    end
  end

  defp require_admin_user(conn, _opts) do
    user = conn.assigns[:current_user]
    
    if user && "admin" in (user.roles || []) do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:error, "You must be an admin to access this page.")
      |> Phoenix.Controller.redirect(to: "/")
      |> halt()
    end
  end
  
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OnelistWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug OnelistWeb.Plugs.SecurityHeaders
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health check - no authentication required
  scope "/", OnelistWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # Protected roadmap with HTTP Basic Auth
  pipeline :roadmap_auth do
    plug OnelistWeb.Plugs.BasicAuth, username: "splntrb", password: "notToday2026!!!"
  end

  scope "/roadmap", OnelistWeb do
    pipe_through [:roadmap_auth]

    get "/", PageController, :roadmap_index
    get "/index.html", PageController, :roadmap_index_html
    get "/:slug", PageController, :roadmap_detail
  end

  # Protected workspace docs with HTTP Basic Auth (stronger password)
  pipeline :workspace_auth do
    plug OnelistWeb.Plugs.BasicAuth, username: "splntrb", password: "slLEcft0LCpFuPOjHWluFfzdcblmhYM9FzZKCvmD"
  end

  scope "/workspace", OnelistWeb do
    pipe_through [:workspace_auth]

    get "/", WorkspaceController, :index
    get "/raw/*path", WorkspaceController, :raw
    get "/*path", WorkspaceController, :show
  end

  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug OnelistWeb.Plugs.ApiAuthenticate
    plug OnelistWeb.Plugs.TrustedMemoryGuard
  end

  # Authentication pipeline for controller-based routes
  pipeline :authenticated do
    plug :browser
    plug OnelistWeb.Plugs.Authenticate
  end

  # Public routes - no authentication required
  scope "/", OnelistWeb do
    pipe_through :browser

    # Marketing pages
    live_session :public, on_mount: [{OnelistWeb.LiveAuth, :maybe_authenticated}] do
      live "/", HomePage
      live "/features", FeaturesPage
      live "/pricing", PricingPage
      live "/documentation", DocumentationPage
    end
    
    # Headwaters waitlist - standalone pages without app chrome
    live_session :waitlist, 
      on_mount: [{OnelistWeb.LiveAuth, :maybe_authenticated}],
      layout: {OnelistWeb.Layouts, :public} do
      live "/waitlist", WaitlistLive
      live "/waitlist/status/:token", WaitlistStatusLive
    end

    # Public Livelog - Stream's conversations in real-time (no auth required)
    live_session :livelog,
      on_mount: [{OnelistWeb.LiveAuth, :maybe_authenticated}],
      layout: {OnelistWeb.Layouts, :public} do
      live "/livelog", LivelogLive
    end

    # Auth routes - redirect if already authenticated
    live_session :redirect_if_authenticated, on_mount: [{OnelistWeb.LiveAuth, :redirect_if_authenticated}] do
      live "/register", Auth.RegistrationPage
      live "/login", Auth.LoginPage
      live "/forgot-password", Auth.PasswordResetPage
      live "/reset-password/:token", Auth.ResetPasswordPage
      live "/verify-email", Auth.EmailVerificationPage
      live "/verify-email/:token", Auth.EmailVerificationPage
      live "/resend-verification", Auth.ResendVerificationPage
    end

    # Session management controller endpoints
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  # Account routes - authentication required
  scope "/account", OnelistWeb do
    pipe_through :browser
    
    # Account management LiveView routes (requires authentication)
    live_session :account_management, on_mount: [{OnelistWeb.LiveAuth, :ensure_authenticated}] do
      live "/sessions", SessionManagementLive
      live "/settings", Account.AccountSettingsPage
    end
  end

  # OAuth routes
  scope "/auth", OnelistWeb do
    pipe_through :browser
    
    # OAuth request and callback routes
    get "/:provider", Auth.OAuthController, :request
    get "/:provider/callback", Auth.OAuthController, :callback
    post "/:provider/callback", Auth.OAuthController, :callback # For Apple POST callback
    
    # Special test routes
    get "/:provider/link", Auth.OAuthController, :handle_github_link
    
    # Account linking
    live_session :link_account, on_mount: [{OnelistWeb.LiveAuth, :maybe_authenticated}] do
      live "/link-account", Auth.LinkAccountLive
    end
  end

  # Protected routes - authentication required
  scope "/app", OnelistWeb do
    pipe_through [:browser, :authenticated]

    # Protected LiveView routes
    live_session :authenticated, on_mount: [{OnelistWeb.LiveAuth, :ensure_authenticated}] do
      live "/dashboard", DashboardLive
      live "/account", AccountLive

      # Social account management
      live "/social-connections", SocialConnectionsLive

      # ============================================
      # NEW APP UI ROUTES
      # ============================================
      
      # Main app views (new UI)
      live "/", App.InboxLive, :index
      live "/library", App.LibraryLive, :index
      live "/library/:id", App.EntryDetailLive, :show
      live "/memories", App.MemoriesLive, :index
      live "/river", App.RiverLive, :index
      live "/search", App.SearchLive, :index
      live "/activity", App.ActivityLive, :index
      live "/settings", App.SettingsLive, :index
      live "/settings/:section", App.SettingsLive, :section
      
      # ============================================
      # LEGACY ROUTES (keep for backwards compat)
      # ============================================

      # Entry management
      live "/entries", Entries.EntryListLive, :index
      live "/entries/new", Entries.EntryEditorLive, :new
      live "/entries/:id/edit", Entries.EntryEditorLive, :edit

      # Tag management
      live "/tags", Tags.TagListLive, :index

      # API Key management
      live "/api-keys", ApiKeys.ApiKeyListLive, :index

      # Account username setup
      live "/account/username", Account.UsernameSetupLive
    end
    
    # Session management routes - controller-based
    get "/sessions", UserSessionController, :index
    delete "/sessions/all", UserSessionController, :delete_all
    delete "/sessions/:id", UserSessionController, :delete
    
    # Privacy and data routes
    get "/account/export-data", PrivacyController, :export_data
    post "/account/delete-account", PrivacyController, :delete_account
    
    # Account management LiveView routes
    live_session :account_settings, on_mount: [{OnelistWeb.LiveAuth, :ensure_authenticated}] do
      live "/settings", Account.AccountSettingsPage
    end
  end

  # Protected API routes - session-based authentication
  scope "/api", OnelistWeb.Api do
    pipe_through [:api, :authenticated]

    post "/sessions/ping", SessionController, :ping
  end

  # API v1 routes - API key authentication
  scope "/api/v1", OnelistWeb.Api.V1, as: :api_v1 do
    pipe_through :api_authenticated

    # User info endpoint (for claude-onelist plugin connection check)
    get "/me", UserController, :me

    resources "/entries", EntryController, except: [:new, :edit] do
      resources "/tags", EntryTagController, only: [:index, :create, :delete]

      resources "/representations", RepresentationController, only: [:index, :show, :update] do
        resources "/versions", RepresentationVersionController, only: [:index, :show]
        post "/versions/:version_id/revert", RepresentationVersionController, :revert
      end

      # Asset routes nested under entries
      resources "/assets", AssetController, only: [:index, :create, :delete]

      # Publish/unpublish routes
      post "/publish", EntryPublishController, :publish
      post "/unpublish", EntryPublishController, :unpublish
      get "/publish-preview", EntryPublishController, :preview
    end

    # Standalone asset routes for download/status
    get "/assets/:id", AssetController, :show
    get "/assets/:id/download", AssetController, :download
    get "/assets/:id/thumbnail", AssetController, :thumbnail
    get "/assets/:id/mirror-status", AssetController, :mirror_status

    resources "/tags", TagController, except: [:new, :edit]

    # Search endpoint
    post "/search", SearchController, :search

    # Similar entries endpoint (nested under entries for clarity)
    get "/entries/:entry_id/similar", SearchController, :similar

    # Chat log streaming (real-time from OpenClaw)
    post "/chat-stream/append", ChatStreamController, :append
    post "/chat-stream/close", ChatStreamController, :close
    get "/chat-stream", ChatStreamController, :index
    get "/chat-stream/recent", ChatStreamController, :recent
    get "/chat-logs", ChatStreamController, :list_logs

    # Embedding management
    get "/embeddings/config", EmbeddingController, :config
    patch "/embeddings/config", EmbeddingController, :update_config
    get "/embeddings/:entry_id", EmbeddingController, :show
    post "/embeddings", EmbeddingController, :create

    # Trusted Memory API
    get "/trusted-memory/status", TrustedMemoryController, :status
    get "/trusted-memory/verify", TrustedMemoryController, :verify
    get "/trusted-memory/audit-log", TrustedMemoryController, :audit_log
    get "/trusted-memory/checkpoints", TrustedMemoryController, :list_checkpoints
    post "/trusted-memory/checkpoint", TrustedMemoryController, :create_checkpoint
    delete "/trusted-memory/checkpoint/:id", TrustedMemoryController, :delete_checkpoint

    # River AI endpoints
    post "/river/chat", RiverController, :chat
    post "/river/chat/stream", RiverController, :chat_stream
    get "/river/context", RiverController, :context
    post "/river/capture", RiverController, :capture
    get "/river/sessions", RiverController, :sessions
    get "/river/sessions/:id", RiverController, :show_session
    post "/river/sessions/:id/close", RiverController, :close_session
    get "/river/gtd-state", RiverController, :gtd_state
    post "/river/weekly-review/complete", RiverController, :complete_review
    
    # River conversations
    get "/river/conversations", RiverController, :list_conversations
    get "/river/conversations/:id", RiverController, :show_conversation
    
    # River tasks (GTD)
    get "/river/tasks", RiverController, :list_tasks
    post "/river/tasks", RiverController, :create_task
    get "/river/tasks/:id", RiverController, :show_task
    patch "/river/tasks/:id", RiverController, :update_task
    post "/river/tasks/:id/complete", RiverController, :complete_task
    
    # River briefings
    get "/river/briefing", RiverController, :briefing

    # Sprint management
    get "/sprints", SprintController, :index
    get "/sprints/:id", SprintController, :show
    get "/sprints/:sprint_id/items", SprintController, :items
    get "/sprints/:sprint_id/blocked", SprintController, :blocked
  end

  # Admin routes
  scope "/admin", OnelistWeb.Admin, as: :admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    live_session :live_admin, on_mount: [{OnelistWeb.LiveAuth, :ensure_authenticated}, {OnelistWeb.LiveAuth, :ensure_admin}] do
      live("/admin_roles", AdminRolesLive, :index)
      # add other admin live routes as needed
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", OnelistWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:onelist, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: OnelistWeb.Telemetry
    end
  end

  # Public entry display - MUST be at the very end to avoid conflicts with other routes
  # This is a catch-all route that matches /:username/:public_id
  scope "/", OnelistWeb do
    pipe_through :browser

    get "/:username/:public_id", PublicEntryController, :show
  end
end
