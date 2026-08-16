defmodule ConduktSite.MixProject do
  use Mix.Project

  # The site depends on the library for the terminal's agent, and a path
  # dependency compiles under this project's environment, so without these the
  # site would force-build both Rust crates from source. It never starts a
  # bashkit or microsandbox sandbox: the terminal's agent has no tools of its
  # own, and the ones the page gives it run in the page. Setting them here
  # keeps a local build, continuous integration, and the release image on the
  # same path, and keeps a Rust toolchain out of the Docker build.
  System.put_env("CONDUKT_BASHKIT_DISABLE", "1")
  System.put_env("CONDUKT_MICROSANDBOX_DISABLE", "1")

  def project do
    [
      app: :condukt_site,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ConduktSite.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.6"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},

      # The agent the home page runs. It used to run in the visitor's browser
      # as WebAssembly built from the Rust crates, which meant a second
      # implementation of the same loop; the site now runs the real one.
      {:condukt, path: "..", override: true},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:req, "~> 0.5"},
      {:mdex, "~> 0.9"},
      {:lumis, "~> 0.6"},
      {:floki, ">= 0.30.0"}
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
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["compile", "esbuild condukt_site"],
      "assets.deploy": ["compile", "esbuild condukt_site --minify", "phx.digest"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
