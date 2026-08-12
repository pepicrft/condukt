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
        description: "Install Condukt and put its terminal coding agent to work in your projects.",
        steps: [
          "Install and connect",
          "Choose a terminal or editor workflow",
          "Automate repeatable tasks"
        ],
        cta: "Start using Condukt",
        href: "/docs/guide"
      },
      %{
        eyebrow: "Agent framework",
        title: "Build your own agent",
        description:
          "Reuse Condukt's state machine while your application owns inference, tools, and presentation.",
        steps: [
          "Understand the host boundary",
          "Provide inference and explicit tools",
          "Embed in a browser or native host"
        ],
        cta: "Start building an agent",
        href: "/docs/reference"
      }
    ]
  end
end
