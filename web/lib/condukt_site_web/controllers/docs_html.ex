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
          "Build an agent on Condukt's own primitives, in Elixir on the BEAM or in Rust and the browser.",
        steps: [
          "Learn the agent loop and the host boundary",
          "Build an OTP agent with the Elixir library",
          "Embed the portable session in a browser or native host"
        ],
        cta: "Start building an agent",
        href: "/docs/framework"
      }
    ]
  end
end
