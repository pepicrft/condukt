defmodule Condukt.Tools do
  @moduledoc """
  Built-in tools for Condukt.

  ## Default Tool Sets

  - `coding_tools/0` - Read, Bash, Edit, Write (default for coding agents)
  - `read_only_tools/0` - Read, Bash (read-only access)

  ## Individual Tools

  - `Condukt.Tools.Read` - Read file contents
  - `Condukt.Tools.Bash` - Execute bash commands
  - `Condukt.Tools.Edit` - Surgical file edits
  - `Condukt.Tools.Write` - Write files

  ## Usage

      defmodule MyAgent do
        use Condukt

        @impl true
        def tools do
          Condukt.Tools.coding_tools()
        end
      end

  Or pick specific tools:

      def tools do
        [
          Condukt.Tools.Read,
          Condukt.Tools.Bash
        ]
      end
  """

  alias Condukt.Tools.{Bash, Edit, Read, Write}

  @doc """
  Returns the default coding tools: Read, Bash, Edit, Write.

  These tools provide full filesystem access for coding agents.
  """
  @spec coding_tools() :: [module()]
  def coding_tools do
    [Read, Bash, Edit, Write]
  end

  @doc """
  Returns read-only tools: Read, Bash.

  Use these when you want the agent to explore but not modify files.
  Note that Bash can still execute arbitrary commands - consider
  implementing command allowlists for production.
  """
  @spec read_only_tools() :: [module()]
  def read_only_tools do
    [Read, Bash]
  end

  @doc """
  Returns all available built-in tools.
  """
  @spec all() :: [module()]
  def all do
    [Read, Bash, Edit, Write]
  end
end
