# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :condukt_site,
  ecto_repos: [ConduktSite.Repo],
  generators: [timestamp_type: :utc_datetime],
  openrouter_model: "openrouter/auto"

# Configure the endpoint
config :condukt_site, ConduktSiteWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ConduktSiteWeb.ErrorHTML, json: ConduktSiteWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ConduktSite.PubSub,
  # Signs the session token a LiveView connection carries. Not a secret in the
  # way `secret_key_base` is, but it must stay stable: changing it invalidates
  # every open connection.
  live_view: [signing_salt: "Nn7pQdVsK2xLmT4c"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  condukt_site: [
    args:
      ~w(js/app.js css/app.css --bundle --format=esm --target=es2022 --outdir=../priv/static/assets --entry-names=[dir]/[name] --external:/fonts/* --external:/images/* --external:/condukt/* --external:https://cdn.jsdelivr.net/gh/lit/dist@3.3.3/core/lit-core.min.js --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :mdex_native, syntax_highlighter: :lumis

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
