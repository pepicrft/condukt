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
  def tab_for_slug("/docs/reference/command-line"), do: :use_condukt

  def tab_for_slug("/docs/guide/" <> page)
      when page in ["how-condukt-works", "browser", "inference"],
      do: :build_agents

  def tab_for_slug("/docs/reference" <> _), do: :build_agents
  def tab_for_slug("/docs/guide" <> _), do: :use_condukt
  def tab_for_slug(_), do: :home

  @spec tree_for_tab(:home | :use_condukt | :build_agents) :: [Group.t()]
  def tree_for_tab(:home), do: home_tree()
  def tree_for_tab(:build_agents), do: build_agents_tree()
  def tree_for_tab(_), do: use_condukt_tree()

  def home_tree do
    [
      %Group{
        label: "Use Condukt",
        icon: "devices_code",
        items: [
          %Item{label: "Coding agent overview", slug: "/docs/guide"},
          %Item{label: "Install and connect", slug: "/docs/guide/getting-started"},
          %Item{label: "Terminal coding agent", slug: "/docs/guide/terminal"}
        ]
      },
      %Group{
        label: "Build agents",
        icon: "subtask",
        items: [
          %Item{label: "Framework overview", slug: "/docs/reference"},
          %Item{label: "Architecture", slug: "/docs/guide/how-condukt-works"},
          %Item{label: "Browser quickstart", slug: "/docs/guide/browser"}
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
          %Item{label: "Overview", slug: "/docs/guide"},
          %Item{label: "Install and connect", slug: "/docs/guide/getting-started"}
        ]
      },
      %Group{
        label: "Work with Condukt",
        icon: "devices_code",
        items: [
          %Item{label: "Terminal coding agent", slug: "/docs/guide/terminal"},
          %Item{label: "Editor integration", slug: "/docs/guide/editor"},
          %Item{label: "Automation", slug: "/docs/guide/automation"}
        ]
      },
      %Group{
        label: "Configuration",
        icon: "settings",
        items: [
          %Item{label: "Providers and credentials", slug: "/docs/guide/credentials"}
        ]
      },
      %Group{
        label: "Reference",
        icon: "list_tree",
        items: [
          %Item{label: "Command-line reference", slug: "/docs/reference/command-line"}
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
          %Item{label: "Overview", slug: "/docs/reference"},
          %Item{label: "Architecture", slug: "/docs/guide/how-condukt-works"},
          %Item{label: "Browser quickstart", slug: "/docs/guide/browser"}
        ]
      },
      %Group{
        label: "Build a host",
        icon: "subtask",
        items: [
          %Item{label: "Provide inference", slug: "/docs/guide/inference"},
          %Item{label: "Define tools", slug: "/docs/reference/tools"},
          %Item{label: "Drive the agent loop", slug: "/docs/reference/host-interface"}
        ]
      },
      %Group{
        label: "Internals",
        icon: "devices_browser",
        items: [
          %Item{label: "Browser package", slug: "/docs/reference/browser-package"},
          %Item{label: "Rust crate architecture", slug: "/docs/reference/internals"}
        ]
      }
    ]
  end
end
