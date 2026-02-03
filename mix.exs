defmodule Onelist.MixProject do
  use Mix.Project

  def project do
    [
      app: :onelist,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Test coverage configuration
      # 75% is realistic for a full-stack app with OAuth and cloud integrations
      # See docs/test_coverage_analysis.md for detailed rationale
      test_coverage: [
        summary: [
          threshold: 75
        ],
        ignore_modules: [
          # Cloud backends - require real AWS/GCS services
          Onelist.Storage.Backends.S3,
          Onelist.Storage.Backends.GCS,
          # Third-party OAuth strategy extension
          Ueberauth.Strategy.Apple,
          # Test infrastructure (not application code)
          Onelist.Test.MockSecurity,
          Onelist.Test.Mocks.Auth.Apple,
          Onelist.Test.Mocks.Auth.Github,
          Onelist.Test.Mocks.Auth.Google,
          Onelist.Test.AuthHelpers,
          Onelist.Test.Mocks.Auth,
          Onelist.Test.PasswordHelpers,
          Onelist.TestHelpers,
          Onelist.TestHelpers.Fixtures,
          Onelist.AccountsFixtures,
          Onelist.EntriesFixtures,
          Onelist.TagsFixtures,
          Onelist.ApiKeysFixtures,
          OnelistWeb.LiveViewTestHelpers,
          OnelistWeb.LiveViewTestHelpers.HostLiveView,
          Onelist.DataCase,
          OnelistWeb.ConnCase
        ]
      ],

      # ExDoc configuration
      name: "Onelist",
      source_url: "https://github.com/trinsiklabs/onelist",
      docs: docs()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Onelist.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # ExDoc documentation configuration
  defp docs do
    [
      main: "readme",
      extras: ["README.md", "docs/api_guide.md"],
      groups_for_modules: [
        Contexts: [
          Onelist.Accounts,
          Onelist.Entries,
          Onelist.Tags,
          Onelist.ApiKeys
        ],
        Schemas: [
          Onelist.Accounts.User,
          Onelist.Entries.Entry,
          Onelist.Entries.Representation,
          Onelist.Entries.RepresentationVersion,
          Onelist.Tags.Tag,
          Onelist.ApiKeys.ApiKey
        ],
        Web: [
          OnelistWeb.Router,
          OnelistWeb.Api.V1.EntryController,
          OnelistWeb.Api.V1.TagController
        ]
      ]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.10"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.1"},
      # HTML parsing for web content capture (used in production and tests)
      {:floki, ">= 0.30.0"},
      {:phoenix_live_dashboard, "~> 0.8.2"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.3"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:plug_cowboy, "~> 2.5"},
      {:bandit, "~> 1.2"},
      # Added for markdown support
      {:earmark, "~> 1.4.48"},
      {:html_sanitize_ex, "~> 1.4"},
      # Added for mocking in tests
      {:mox, "~> 1.1", only: :test},
      {:meck, "~> 0.9.2", only: :test},
      # Added for OAuth social login
      {:ueberauth, "~> 0.10.0"},
      {:ueberauth_github, "~> 0.8.0"},
      {:ueberauth_google, "~> 0.10.0"},
      # For Apple JWT verification
      {:joken, "~> 2.5"},
      # {:x509, "~> 0.9.2"},  # For Apple certificate validation - disabled until OTP 28.0.2+ available
      # Password hashing
      {:argon2_elixir, "~> 3.0"},
      {:bcrypt_elixir, "~> 3.0"},
      # HTTP client for API calls
      {:httpoison, "~> 2.0"},
      # Background job processing
      {:oban, "~> 2.17"},
      # Diff generation for version control
      {:diffy, "~> 1.1"},
      # Storage backends (S3, GCS)
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},
      {:hackney, "~> 1.20"},
      {:mime, "~> 2.0"},
      # Google Cloud Storage (optional, uses API directly)
      {:goth, "~> 1.4", optional: true},
      # Documentation generation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      # Vector embeddings for semantic search
      {:pgvector, "~> 0.3"},
      # HTTP client for API calls (OpenAI, etc.)
      {:req, "~> 0.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
