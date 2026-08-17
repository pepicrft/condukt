defmodule ConduktSiteWeb.DocsHTML do
  @moduledoc "HTML templates for Condukt documentation."

  use ConduktSiteWeb, :html

  import ConduktSiteWeb.Docs.Components

  embed_templates "docs_html/*"

  def persona_cards do
    [
      %{
        eyebrow: "Start here",
        title: "Build an agent",
        description:
          "Define an agent module, give it tools, and run it inside your own supervision tree.",
        steps: [
          "Install the Hex package",
          "Define an agent and give it tools",
          "Stream a conversation and keep it alive"
        ],
        cta: "Start building an agent",
        href: "/docs/framework"
      },
      %{
        eyebrow: "Run it safely",
        title: "Contain the work",
        description:
          "Decide where an agent's tools run and what they can reach, separately from what the agent is asked to do.",
        steps: [
          "Run tools in a sandbox rather than on the host",
          "Set per-session network policy",
          "Resolve secrets and keep them out of transcripts"
        ],
        cta: "Read about sandboxes",
        href: "/docs/framework/elixir/sandbox"
      }
    ]
  end
end
