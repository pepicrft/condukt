defmodule Condukt.ToolTest do
  use ExUnit.Case, async: true

  alias Condukt.Tool
  alias Condukt.Tools.Command
  alias Condukt.Tools.Read

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
end
