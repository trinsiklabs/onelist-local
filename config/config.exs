# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :onelist,
  ecto_repos: [Onelist.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configures the endpoint
config :onelist, OnelistWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: OnelistWeb.ErrorHTML, json: OnelistWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Onelist.PubSub,
  live_view: [signing_salt: "g55UczKX"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :onelist, Onelist.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  onelist: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  onelist: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth OAuth providers
config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, [default_scope: "user:email", use_pkce: true]},
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile", use_pkce: true]},
    apple: {Ueberauth.Strategy.Apple, [use_pkce: true]}
  ]

# Configure GitHub OAuth
config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET")

# Configure Google OAuth
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

# Configure Apple Sign In
config :onelist, :apple_auth,
  client_id: System.get_env("APPLE_CLIENT_ID"),
  team_id: System.get_env("APPLE_TEAM_ID"),
  key_id: System.get_env("APPLE_KEY_ID"),
  private_key: System.get_env("APPLE_PRIVATE_KEY")

# Configure Oban for background job processing
config :onelist, Oban,
  repo: Onelist.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Daily snapshot sweep at 3 AM
       {"0 3 * * *", Onelist.Workers.SnapshotWorker, args: %{"action" => "sweep"}},
       # Storage cleanup every 15 minutes
       {"*/15 * * * *", Onelist.Workers.StorageCleanupWorker},
       # Close inactive chat logs every 30 minutes
       {"*/30 * * * *", Onelist.Workers.CloseChatLogsWorker}
     ]}
  ],
  queues: [
    default: 10,
    snapshots: 5,
    storage: 10,
    embeddings: 5,
    embeddings_batch: 2,
    enrichment: 5,
    enrichment_audio: 2,
    enrichment_image: 3,
    enrichment_document: 3,
    reader: 5,
    capture: 5,
    feeder: 5
  ]

# Configure Searcher agent for embedding and search
config :onelist, :searcher,
  embedding_model: "text-embedding-3-small",
  embedding_dimensions: 1536,
  default_search_type: "hybrid",
  default_semantic_weight: 0.7,
  default_keyword_weight: 0.3,
  max_chunk_tokens: 500,
  chunk_overlap_tokens: 50,
  auto_embed_on_create: true,
  auto_embed_on_update: true

# Configure Reader agent for memory extraction
config :onelist, :reader,
  extraction_model: "gpt-4o-mini",
  default_summary_style: "concise",
  max_tag_suggestions: 5,
  auto_process_on_create: true,
  auto_process_on_update: true

# Configure asset storage
config :onelist, Onelist.Storage,
  primary_backend: :local,
  mirror_backends: [],
  enable_e2ee: false,
  enable_tiered_sync: false,
  max_local_asset_size: 1_000_000

config :onelist, Onelist.Storage.Backends.Local,
  root_path: "priv/static/uploads"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
