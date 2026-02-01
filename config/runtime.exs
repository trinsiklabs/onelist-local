import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/onelist start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :onelist, OnelistWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :onelist, Onelist.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :onelist, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :onelist, OnelistWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Bind to localhost only - nginx handles public traffic
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {127, 0, 0, 1},
      port: port
    ],
    secret_key_base: secret_key_base,
    # Force SSL and enable HSTS (HTTP Strict Transport Security)
    force_ssl: [
      hsts: true,
      # 1 year max-age, include subdomains, allow preload list submission
      expires: 31_536_000,
      subdomains: true,
      preload: true
    ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :onelist, OnelistWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :onelist, OnelistWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :onelist, Onelist.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  # ## Storage Configuration
  #
  # Configure the primary storage backend and mirrors.
  # STORAGE_BACKEND can be: local, s3
  # For S3-compatible services (R2, B2, Spaces), use s3 with custom endpoint.

  storage_backend =
    case System.get_env("STORAGE_BACKEND", "local") do
      "s3" -> :s3
      "gcs" -> :gcs
      _ -> :local
    end

  mirror_backends =
    case System.get_env("STORAGE_MIRRORS", "") do
      "" -> []
      mirrors -> String.split(mirrors, ",") |> Enum.map(&String.to_atom/1)
    end

  config :onelist, Onelist.Storage,
    primary_backend: storage_backend,
    mirror_backends: mirror_backends,
    enable_e2ee: System.get_env("STORAGE_E2EE_ENABLED", "false") == "true",
    enable_tiered_sync: System.get_env("STORAGE_TIERED_SYNC", "false") == "true",
    max_local_asset_size: String.to_integer(System.get_env("STORAGE_MAX_LOCAL_SIZE", "1000000"))

  # Local storage configuration
  if local_path = System.get_env("STORAGE_LOCAL_PATH") do
    config :onelist, Onelist.Storage.Backends.Local,
      root_path: local_path
  end

  # S3/S3-compatible storage configuration
  # Works with: AWS S3, Cloudflare R2, Backblaze B2, DigitalOcean Spaces, MinIO, Wasabi
  if System.get_env("S3_BUCKET") do
    s3_config = [
      bucket: System.get_env("S3_BUCKET"),
      region: System.get_env("S3_REGION", "us-east-1"),
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
    ]

    # Add custom endpoint for S3-compatible services
    s3_config =
      case System.get_env("S3_ENDPOINT") do
        nil -> s3_config
        endpoint -> Keyword.put(s3_config, :endpoint, endpoint)
      end

    config :onelist, Onelist.Storage.Backends.S3, s3_config
  end

  # ExAws configuration for S3
  if System.get_env("AWS_ACCESS_KEY_ID") do
    config :ex_aws,
      access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
      secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
      region: System.get_env("S3_REGION", "us-east-1")

    # Custom S3 host for S3-compatible services
    if endpoint = System.get_env("S3_ENDPOINT") do
      uri = URI.parse(endpoint)

      config :ex_aws, :s3,
        scheme: uri.scheme || "https://",
        host: uri.host,
        port: uri.port || 443
    end
  end

  # OpenAI API configuration for Searcher agent
  if openai_key = System.get_env("OPENAI_API_KEY") do
    config :onelist, :openai_api_key, openai_key
  end
end
