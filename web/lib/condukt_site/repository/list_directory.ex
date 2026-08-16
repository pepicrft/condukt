defmodule ConduktSite.Repository.ListDirectory do
  @moduledoc """
  Lists a directory in Condukt's public repository.

  One of the two tools the home page's agent is given. Read-only, and scoped to
  a single public repository, so it carries no authority over the server it runs
  on.
  """

  use Condukt.Tool

  alias ConduktSite.Repository

  @impl Condukt.Tool
  def name, do: "list_repository_directory"

  @impl Condukt.Tool
  def description do
    source = Repository.source()

    "List the files and directories at a path in the #{source.repository} repository " <>
      "at revision #{source.revision}. Use an empty path for the repository root."
  end

  @impl Condukt.Tool
  def parameters do
    %{
      type: "object",
      properties: %{
        path: %{
          type: "string",
          description:
            "Directory path relative to the repository root, or an empty string for the root."
        }
      },
      required: []
    }
  end

  @impl Condukt.Tool
  def call(args, _context) do
    case Repository.list_directory(Map.get(args, "path", "")) do
      {:ok, entries} -> {:ok, %{entries: entries}}
      {:error, reason} -> {:error, reason}
    end
  end
end
