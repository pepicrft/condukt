defmodule ConduktSite.Repository.ReadFile do
  @moduledoc """
  Reads a text file from Condukt's public repository.

  The other half of what the home page's agent can do. Read-only, and scoped to
  a single public repository.
  """

  use Condukt.Tool

  alias ConduktSite.Repository

  @impl Condukt.Tool
  def name, do: "read_repository_file"

  @impl Condukt.Tool
  def description do
    source = Repository.source()

    "Read a text file from the #{source.repository} repository at revision #{source.revision}."
  end

  @impl Condukt.Tool
  def parameters do
    %{
      type: "object",
      properties: %{
        path: %{type: "string", description: "Text file path relative to the repository root."}
      },
      required: ["path"]
    }
  end

  @impl Condukt.Tool
  def call(%{"path" => path}, _context), do: Repository.read_file(path)

  def call(_args, _context), do: {:error, "a path is required"}
end
