defmodule Glossia.Agent.Tools.ReadTest do
  use Glossia.Agent.ToolCase

  alias Glossia.Agent.Tools.Read

  test "reads file contents", %{cwd: cwd} do
    path = Path.join(cwd, "test.txt")
    File.write!(path, "Hello, World!")

    context = %{cwd: cwd, opts: []}
    {:ok, result} = Read.call(%{"path" => "test.txt"}, context)

    assert result == "Hello, World!"
  end

  test "reads with offset and limit", %{cwd: cwd} do
    path = Path.join(cwd, "lines.txt")
    File.write!(path, "line1\nline2\nline3\nline4\nline5")

    context = %{cwd: cwd, opts: []}
    {:ok, result} = Read.call(%{"path" => "lines.txt", "offset" => 2, "limit" => 2}, context)

    assert String.contains?(result, "line2")
    assert String.contains?(result, "line3")
    refute String.contains?(result, "line1")
    refute String.contains?(result, "line4")
  end

  test "returns error for missing file", %{cwd: cwd} do
    context = %{cwd: cwd, opts: []}
    {:error, error} = Read.call(%{"path" => "missing.txt"}, context)

    assert String.contains?(error, "not found")
  end

  test "returns error for directory", %{cwd: cwd} do
    context = %{cwd: cwd, opts: []}
    {:error, error} = Read.call(%{"path" => "."}, context)

    assert String.contains?(error, "directory")
  end
end
