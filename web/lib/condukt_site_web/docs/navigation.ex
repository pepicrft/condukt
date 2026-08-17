defmodule ConduktSiteWeb.Docs.Navigation do
  @moduledoc "Documentation tabs and sidebar navigation."

  defmodule Item do
    @moduledoc false
    defstruct [:label, :slug]
    @type t :: %__MODULE__{label: String.t(), slug: String.t()}
  end

  defmodule Group do
    @moduledoc false
    defstruct [:label, :icon, items: []]

    @type t :: %__MODULE__{
            label: String.t(),
            icon: String.t(),
            items: [ConduktSiteWeb.Docs.Navigation.Item.t()]
          }
  end

  alias __MODULE__.{Group, Item}

  @spec tab_for_slug(String.t()) :: :home | :use_condukt | :build_agents
  def tab_for_slug("/docs/cli" <> _), do: :use_condukt
  def tab_for_slug("/docs/framework" <> _), do: :build_agents
  def tab_for_slug(_), do: :home

  @spec tree_for_tab(:home | :use_condukt | :build_agents) :: [Group.t()]
  def tree_for_tab(:home), do: home_tree()
  def tree_for_tab(:build_agents), do: build_agents_tree()
  def tree_for_tab(_), do: use_condukt_tree()

  def home_tree do
    [
      %Group{
        label: "Build agents",
        icon: "subtask",
        items: [
          %Item{label: "Framework overview", slug: "/docs/framework"},
          %Item{label: "Architecture", slug: "/docs/framework/architecture"},
          %Item{label: "Elixir library", slug: "/docs/framework/elixir"}
        ]
      },
      %Group{
        label: "Use Condukt",
        icon: "device_desktop",
        items: [
          %Item{label: "Coding agent overview", slug: "/docs/cli"},
          %Item{label: "Install and connect", slug: "/docs/cli/getting-started"},
          %Item{label: "Terminal coding agent", slug: "/docs/cli/terminal"}
        ]
      }
    ]
  end

  def use_condukt_tree do
    [
      %Group{
        label: "Start here",
        icon: "book_2",
        items: [
          %Item{label: "Overview", slug: "/docs/cli"},
          %Item{label: "Install and connect", slug: "/docs/cli/getting-started"}
        ]
      },
      %Group{
        label: "Work with Condukt",
        icon: "device_desktop",
        items: [
          %Item{label: "Terminal coding agent", slug: "/docs/cli/terminal"},
          %Item{label: "Editor integration", slug: "/docs/cli/editor"},
          %Item{label: "Automation", slug: "/docs/cli/automation"}
        ]
      },
      %Group{
        label: "Configuration",
        icon: "settings",
        items: [
          %Item{label: "Providers and credentials", slug: "/docs/cli/credentials"}
        ]
      },
      %Group{
        label: "Reference",
        icon: "list_tree",
        items: [
          %Item{label: "Command-line reference", slug: "/docs/cli/command-line"}
        ]
      }
    ]
  end

  def build_agents_tree do
    [
      %Group{
        label: "Start here",
        icon: "book_2",
        items: [
          %Item{label: "Framework overview", slug: "/docs/framework"},
          %Item{label: "Architecture", slug: "/docs/framework/architecture"}
        ]
      },
      %Group{
        label: "Elixir library",
        icon: "atom",
        items: [
          %Item{label: "Overview", slug: "/docs/framework/elixir"},
          %Item{label: "Installation", slug: "/docs/framework/elixir/installation"},
          %Item{label: "Getting started", slug: "/docs/framework/elixir/getting-started"},
          %Item{label: "Agents", slug: "/docs/framework/elixir/agents"},
          %Item{label: "One-shot runs", slug: "/docs/framework/elixir/one-shot-runs"},
          %Item{label: "Tools", slug: "/docs/framework/elixir/tools"},
          %Item{label: "Sub-agents", slug: "/docs/framework/elixir/subagents"}
        ]
      },
      %Group{
        label: "Elixir integrations",
        icon: "api",
        items: [
          %Item{label: "Providers", slug: "/docs/framework/elixir/providers"},
          %Item{label: "MCP servers", slug: "/docs/framework/elixir/mcp"},
          %Item{label: "HTTP routes", slug: "/docs/framework/elixir/http-routes"}
        ]
      },
      %Group{
        label: "Elixir isolation",
        icon: "lock",
        items: [
          %Item{label: "Sandboxes", slug: "/docs/framework/elixir/sandbox"},
          %Item{label: "Network policy", slug: "/docs/framework/elixir/network-policy"},
          %Item{label: "Secrets", slug: "/docs/framework/elixir/secrets"},
          %Item{label: "Redaction", slug: "/docs/framework/elixir/redaction"}
        ]
      },
      %Group{
        label: "Elixir runtime",
        icon: "server",
        items: [
          %Item{
            label: "Sessions and persistence",
            slug: "/docs/framework/elixir/sessions-and-persistence"
          },
          %Item{
            label: "Streaming and events",
            slug: "/docs/framework/elixir/streaming-and-events"
          },
          %Item{label: "Compaction", slug: "/docs/framework/elixir/compaction"},
          %Item{
            label: "Project instructions",
            slug: "/docs/framework/elixir/project-instructions"
          },
          %Item{label: "Telemetry", slug: "/docs/framework/elixir/telemetry"}
        ]
      }
    ]
  end
end
