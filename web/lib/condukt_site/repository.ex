defmodule ConduktSite.Repository do
  @moduledoc """
  The repository the terminal's agent reads.

  The reading itself happens in the visitor's browser, in
  `assets/js/repository_tools.mjs`. This is the same pin, held server-side for
  the copy on the page and the agent's system prompt, so the two cannot drift
  into describing different things.
  """

  @repository "tuist/condukt"
  @revision "main"

  @doc "The repository and revision the terminal's tools read."
  def source, do: %{repository: @repository, revision: @revision}
end
