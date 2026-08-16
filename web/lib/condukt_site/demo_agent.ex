defmodule ConduktSite.DemoAgent do
  @moduledoc """
  The agent behind the terminal on the home page.

  It is a real `Condukt` agent, not a demonstration of one: the same session,
  the same turn loop, the same tool dispatch the terminal agent and any
  consumer of the library use. The only thing specific to this surface is what
  it can reach, which is two read-only views of Condukt's own public
  repository.

  That narrowness is the point. The agent runs on the server, so anything it
  could touch would be the server's, and it is given nothing that belongs to
  the machine: no filesystem, no shell, no network beyond one public
  repository. A visitor cannot make it do anything a visitor should not.

  Inference is billed to the visitor's own OpenRouter credential, supplied
  through the sign-in flow and passed to the session at start.
  """

  use Condukt.Agent

  alias ConduktSite.Repository

  @impl Condukt
  def model, do: "openrouter:" <> Application.fetch_env!(:condukt_site, :openrouter_model)

  @impl Condukt
  def tools, do: [Repository.ListDirectory, Repository.ReadFile]

  @impl Condukt
  def system_prompt do
    source = Repository.source()

    """
    You are Condukt, answering questions about your own source in the
    #{source.repository} repository at revision #{source.revision}.

    You can list directories and read text files there, and nothing else. Look
    before answering: read the code rather than describing what a project like
    this usually does. When a question is outside what the repository can
    answer, say so instead of guessing.

    Keep answers short. This is a terminal on a web page, and the person
    reading has a few lines of room.
    """
  end
end
