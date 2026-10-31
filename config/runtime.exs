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
#     PHX_SERVER=true bin/patchwrit_api start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :patchwrit_api, PatchwritApiWeb.Endpoint, server: true
end

config :patchwrit_api, PatchwritApiWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Fly Machines API (Phase 3 client). Secrets come from the environment only.
# Guarded so test/dev config is never clobbered when the vars are absent.
if System.get_env("FLY_API_TOKEN") || System.get_env("FLY_APP_NAME") do
  config :patchwrit_api, :fly,
    api_token: System.get_env("FLY_API_TOKEN"),
    app_name: System.get_env("FLY_APP_NAME"),
    base_url: System.get_env("FLY_API_HOSTNAME") || "https://api.machines.dev",
    worker_image: System.get_env("WORKER_IMAGE"),
    worker_images: %{
      "smoke" => System.get_env("WORKER_IMAGE_SMOKE") || System.get_env("WORKER_IMAGE"),
      "jdk17" => System.get_env("WORKER_IMAGE_JDK17"),
      "jdk21" => System.get_env("WORKER_IMAGE_JDK21")
    }
end

# Meta Model API (tribunal). Phoenix-side only: the key is never sent
# to a worker. Guarded so test/dev config is never clobbered when absent.
if System.get_env("MODEL_API_KEY") do
  config :patchwrit_api, :meta,
    api_key: System.get_env("MODEL_API_KEY"),
    base_url: System.get_env("META_MODEL_BASE_URL") || "https://api.meta.ai/v1",
    advocate_model: System.get_env("META_ADVOCATE_MODEL") || "muse-spark-1.3",
    judge_model: System.get_env("META_JUDGE_MODEL") || "muse-wonder-1.0",
    prompt_cache_retention: System.get_env("META_PROMPT_CACHE_RETENTION") || "in_memory"
end

# Public base URL workers use to call back (tunnel in dev, deployed app in prod).
if base = System.get_env("CALLBACK_BASE_URL") do
  config :patchwrit_api, :callback_base_url, base
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :patchwrit_api, PatchwritApi.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
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

  config :patchwrit_api, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :patchwrit_api, PatchwritApiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :patchwrit_api, PatchwritApiWeb.Endpoint,
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
  #     config :patchwrit_api, PatchwritApiWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :patchwrit_api, PatchwritApi.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

# Bearer gate for test-machine routes outside dev (never commit the value).
if token = System.get_env("TEST_MACHINES_TOKEN") do
  config :patchwrit_api, test_machines_token: token
end

# Optional GitHub token for higher API rate limits. Public metadata works
# without it; the token is server-side only and never sent to a worker.
if github_token = System.get_env("GITHUB_TOKEN") do
  config :patchwrit_api, :github, token: github_token
end
