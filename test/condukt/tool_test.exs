defmodule Condukt.ToolTest do
  use ExUnit.Case, async: true

  alias Condukt.Tool
  alias Condukt.Tools.Command
  alias Condukt.Tools.Read

  defmodule RaisingTool do
    use Condukt.Tool

    @impl true
    def name, do: "RaisingTool"

    @impl true
    def description, do: "Raises while executing"

    @impl true
    def parameters, do: %{type: "object", properties: %{}}

    @impl true
    def call(_args, _context), do: raise("boom")
  end

  test "builds spec from module" do
    spec = Tool.to_spec(Read)

    assert spec.name == "Read"
    assert is_binary(spec.description)
    assert is_map(spec.parameters)
  end

  test "builds spec from a parameterized command tool" do
    spec = Tool.to_spec({Command, command: "git"})

    assert spec.name == "Git"
    assert spec.description =~ "`git`"
    assert spec.parameters[:properties][:args][:type] == "array"
  end

  test "returns an error tuple when a tool raises" do
    assert {:error, "boom"} = Tool.execute(RaisingTool, %{}, %{agent: self(), cwd: ".", opts: []})
  end
end
