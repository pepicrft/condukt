import Config

alias ConduktSite.Config.DevInstance

Code.require_file("dev_instance.exs", __DIR__)

config :condukt_site, ConduktSite.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database:
    DevInstance.database_name(
      "condukt_site_test",
      partition: System.get_env("MIX_TEST_PARTITION")
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: String.to_integer(System.get_env("CONDUKT_DATABASE_POOL_SIZE", "2"))

config :condukt_site,
  openrouter_request_options: [plug: {Req.Test, ConduktSite.OpenRouter}]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :condukt_site, ConduktSiteWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: DevInstance.port(4002)],
  secret_key_base: "534NXstquoIXpqu6mfQ/yKOz7nFtBBijzOo57iDiMcBK4kod3Ds6VfPwiFaq9F4G",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
