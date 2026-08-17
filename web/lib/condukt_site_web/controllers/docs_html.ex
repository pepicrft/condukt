defmodule ConduktSiteWeb.DocsHTML do
  @moduledoc "HTML templates for Condukt documentation."

  use ConduktSiteWeb, :html

  import ConduktSiteWeb.Docs.Components

  embed_templates "docs_html/*"

  def persona_cards do
    [
      %{
        eyebrow: "Agent framework",
        title: "Build an agent",
        description:
          "Build an agent in Elixir whose tools run in a sandbox, on a network you decide, inside your own supervision tree.",
        steps: [
          "Define an agent and give it tools",
          "Contain the work with sandboxes and network policy",
          "Keep a conversation alive with sessions and persistence"
        ],
        cta: "Start building an agent",
        href: "/docs/framework"
      },
      %{
        eyebrow: "Coding agent",
        title: "Use the terminal agent",
        description:
          "Install the coding agent built on the library, the fullest worked example of a host.",
        steps: [
          "Install and connect",
          "Choose a terminal or editor workflow",
          "Automate repeatable tasks"
        ],
        cta: "Start using Condukt",
        href: "/docs/cli"
      }
    ]
  end
end
