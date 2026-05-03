defmodule Condukt.MixProject do
  use Mix.Project

  @version "0.13.0"
  @source_url "https://github.com/tuist/condukt"

  def project do
    [
      app: :condukt,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "Condukt",
      description: "A framework for building AI agents in Elixir",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {Condukt.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # LLM client (supports Anthropic, OpenAI, Google, and 15+ more providers)
      {:req_llm, "~> 1.6"},

      # JSON Schema validation for operation input/output
      {:jsv, "~> 0.16"},

      # Command execution with child process shutdown propagation
      {:muontrap, "~> 1.7"},

      # Telemetry
      {:telemetry, "~> 1.0"},

      # Development & Testing
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.0", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "guides/getting_started.md": [title: "Getting Started"],
        "guides/agents.md": [title: "Agents"],
        "guides/tools.md": [title: "Tools"],
        "guides/streaming_and_events.md": [title: "Streaming and Events"],
        "guides/sessions_and_persistence.md": [title: "Sessions and Persistence"],
        "guides/compaction.md": [title: "Compaction"],
        "guides/redaction.md": [title: "Redaction"],
        "guides/project_instructions.md": [title: "Project Instructions"],
        "guides/telemetry.md": [title: "Telemetry"],
        "guides/providers.md": [title: "Providers"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      groups_for_extras: [
        Introduction: [
          "README.md",
          "guides/getting_started.md"
        ],
        Guides: [
          "guides/agents.md",
          "guides/tools.md",
          "guides/streaming_and_events.md",
          "guides/sessions_and_persistence.md",
          "guides/compaction.md",
          "guides/redaction.md",
          "guides/project_instructions.md",
          "guides/telemetry.md",
          "guides/providers.md"
        ],
        Reference: [
          "CHANGELOG.md"
        ]
      ],
      source_ref: @version,
      source_url: @source_url,
      groups_for_modules: [
        Core: [
          Condukt,
          Condukt.Session,
          Condukt.Operation,
          Condukt.Message,
          Condukt.Telemetry
        ],
        "Project Context": [
          Condukt.Context,
          Condukt.Context.Skill
        ],
        Tools: [
          Condukt.Tool,
          Condukt.Tools,
          Condukt.Tools.Read,
          Condukt.Tools.Bash,
          Condukt.Tools.Command,
          Condukt.Tools.Edit,
          Condukt.Tools.Write
        ],
        "Session Stores": [
          Condukt.SessionStore,
          Condukt.SessionStore.Snapshot,
          Condukt.SessionStore.Memory,
          Condukt.SessionStore.Disk
        ],
        Compaction: [
          Condukt.Compactor,
          Condukt.Compactor.Sliding,
          Condukt.Compactor.ToolResultPrune
        ],
        Redaction: [
          Condukt.Redactor,
          Condukt.Redactors.Regex
        ],
        Providers: [
          Condukt.Providers.Ollama
        ]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib guides .formatter.exs mix.exs README.md CHANGELOG.md LICENSE MIT.md)
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end
end
