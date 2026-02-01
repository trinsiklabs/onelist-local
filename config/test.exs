import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :onelist, Onelist.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "onelist_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :onelist, OnelistWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "rwIw6330ZWAftKpNgJTfhp6dSI9F+nDIu1fShpYjS584KPAXKGAk5Wi+zUGhTYDq",
  server: true,
  live_view: [
    signing_salt: "aaaaaaaa",
    debug_heex_annotations: true
  ],
  pubsub_server: Onelist.PubSub,
  render_errors: [
    formats: [html: OnelistWeb.ErrorHTML],
    layout: false
  ]

# Configure the accounts module to use the mock in tests
config :onelist, :accounts, Onelist.AccountsMock

# Configure test password hashing
config :onelist, :password_hash_algorithm, :test
config :onelist, :test_password_hasher, Onelist.Test.PasswordHelpers

# In test we don't send emails
config :onelist, Onelist.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Configure OAuth test settings
config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: "test_github_client_id",
  client_secret: "test_github_client_secret"

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: "test_google_client_id",
  client_secret: "test_google_client_secret"

config :onelist, :apple_auth,
  client_id: "test_apple_client_id",
  team_id: "test_apple_team_id",
  key_id: "test_apple_key_id",
  private_key: "test_apple_private_key"

# Configure OAuth API modules for mocking
config :onelist, :github_api, Onelist.Auth.GithubMock
config :onelist, :google_api, Onelist.Auth.GoogleMock
config :onelist, :apple_api, Onelist.Auth.AppleMock

# Ensure the env is set to :test for OAuth controller
config :onelist, env: :test

# Flag to indicate SQL sandbox mode for async task handling
config :onelist, :sql_sandbox, true

# Configure Oban for testing (inline execution, no plugins)
config :onelist, Oban,
  testing: :inline,
  plugins: false,
  queues: false

# Skip auto-processing entirely in tests (avoids hitting real APIs with inline Oban)
config :onelist, :skip_auto_processing, true

# Configure storage for testing
config :onelist, Onelist.Storage,
  primary_backend: :local,
  mirror_backends: [],
  enable_e2ee: false,
  enable_tiered_sync: false

config :onelist, Onelist.Storage.Backends.Local,
  root_path: "priv/static/uploads/test"
