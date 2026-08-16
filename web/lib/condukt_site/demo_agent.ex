defmodule ConduktSite.DemoAgent do
  @moduledoc """
  The agent behind the terminal on the home page.

  It is a real `Condukt` agent, not a demonstration of one: the same session,
  the same turn loop, the same tool dispatch the terminal agent and any
  consumer of the library use.

  It declares no tools. What it can reach is whatever the visitor's page
  declares when it connects, built into tools by `ConduktSite.BrowserTools` and
  passed to the session at start. The loop runs on the server; the reading
  happens in the browser, on the visitor's own address. So the agent holds
  nothing belonging to the machine it runs on: no filesystem, no shell, no
  network of its own.

  Inference is billed to the visitor's own OpenRouter credential, supplied
  through the sign-in flow and passed to the session at start.
  """

  use Condukt.Agent

  alias ConduktSite.Repository

  @impl Condukt
  def model, do: "openrouter:" <> Application.fetch_env!(:condukt_site, :openrouter_model)

  @impl Condukt
  def system_prompt do
    source = Repository.source()

    """
    You are Condukt, answering questions about your own source in the
    #{source.repository} repository at revision #{source.revision}.

    Your tools read that repository and nothing else. Look before answering:
    read the code rather than describing what a project like this usually does.
    When a question is outside what the repository can answer, say so instead
    of guessing.

    Keep answers short. This is a terminal on a web page, and the person
    reading has a few lines of room.
    """
  end
end
