defmodule Condukt.Tools do
  @moduledoc """
  Built-in tools for Condukt.

  ## Default Tool Sets

  - `coding_tools/0` - Read, Bash, Edit, Write (default for coding agents)
  - `read_only_tools/0` - Read, Bash (read-only access)
  - `command/2` - Build a scoped command tool for a trusted executable

  ## Individual Tools

  - `Condukt.Tools.Read` - Read file contents
  - `Condukt.Tools.Bash` - Execute bash commands
  - `Condukt.Tools.Command` - Execute one trusted command without shell parsing
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

  alias Condukt.Tools.{Bash, Command, Edit, Read, Write}

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
  Note that Bash can still execute arbitrary commands. Prefer `command/2`
  when you want to grant a specific executable such as `git`, `gh`, or `mix`.
  """
  @spec read_only_tools() :: [module()]
  def read_only_tools do
    [Read, Bash]
  end

  @doc """
  Returns a parameterized scoped command tool.

  Use this to expose one trusted executable without shell parsing:

      def tools do
        [
          Condukt.Tools.Read,
          Condukt.Tools.command("git"),
          Condukt.Tools.command("gh", env: [GH_TOKEN: System.fetch_env!("GH_TOKEN")])
        ]
      end
  """
  def command(command, opts \\ []) do
    {Command, Keyword.put_new(opts, :command, command)}
  end

  @doc """
  Returns all available built-in tools.
  """
  @spec all() :: [module()]
  def all do
    [Read, Bash, Edit, Write]
  end
end
