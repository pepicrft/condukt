defmodule Glossia.Agent.Tools.BashTest do
  use Glossia.Agent.ToolCase

  alias Glossia.Agent.Tools.Bash

  test "executes simple command", %{cwd: cwd} do
    context = %{cwd: cwd, opts: []}
    {:ok, result} = Bash.call(%{"command" => "echo hello"}, context)

    assert String.contains?(result, "hello")
  end

  test "captures stderr", %{cwd: cwd} do
    context = %{cwd: cwd, opts: []}
    {:ok, result} = Bash.call(%{"command" => "echo error >&2"}, context)

    assert String.contains?(result, "error")
  end

  test "returns exit code for failures", %{cwd: cwd} do
    context = %{cwd: cwd, opts: []}
    {:ok, result} = Bash.call(%{"command" => "exit 42"}, context)

    assert String.contains?(result, "exit code: 42")
  end

  test "respects cwd", %{cwd: cwd} do
    context = %{cwd: cwd, opts: []}
    {:ok, result} = Bash.call(%{"command" => "pwd"}, context)

    assert String.contains?(result, cwd)
  end
end
