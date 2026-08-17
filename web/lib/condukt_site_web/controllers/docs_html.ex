defmodule ConduktSiteWeb.DocsHTML do
  @moduledoc "HTML templates for Condukt documentation."

  use ConduktSiteWeb, :html

  import ConduktSiteWeb.Docs.Components

  embed_templates "docs_html/*"

  def persona_cards do
    [
      %{
        eyebrow: "Coding agent",
        title: "Use Condukt",
        description:
          "Install Condukt and put its terminal coding agent to work in your projects.",
        steps: [
          "Install and connect",
          "Choose a terminal or editor workflow",
          "Automate repeatable tasks"
        ],
        cta: "Start using Condukt",
        href: "/docs/cli"
      },
      %{
        eyebrow: "Agent framework",
        title: "Build your own agent",
        description:
          "Build an agent on the same Elixir library the coding agent runs on, with supervised sessions and sandboxed tools.",
        steps: [
          "Learn the agent loop and the host boundary",
          "Build an OTP agent with the Elixir library",
          "Control what an agent can reach with sandboxes and network policy"
        ],
        cta: "Start building an agent",
        href: "/docs/framework"
      }
    ]
  end
end
