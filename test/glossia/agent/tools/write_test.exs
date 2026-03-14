defmodule Glossia.Agent.Tools.WriteTest do
  use Glossia.Agent.ToolCase

  alias Glossia.Agent.Tools.Write

  test "creates new file", %{cwd: cwd} do
    context = %{cwd: cwd, opts: []}
    {:ok, result} = Write.call(%{"path" => "new.txt", "content" => "Hello!"}, context)

    assert String.contains?(result, "Created")
    assert File.read!(Path.join(cwd, "new.txt")) == "Hello!"
  end

  test "overwrites existing file", %{cwd: cwd} do
    path = Path.join(cwd, "existing.txt")
    File.write!(path, "old content")

    context = %{cwd: cwd, opts: []}
    {:ok, result} = Write.call(%{"path" => "existing.txt", "content" => "new content"}, context)

    assert String.contains?(result, "Updated")
    assert File.read!(path) == "new content"
  end

  test "creates parent directories", %{cwd: cwd} do
    context = %{cwd: cwd, opts: []}
    {:ok, _result} = Write.call(%{"path" => "deep/nested/file.txt", "content" => "nested"}, context)

    assert File.read!(Path.join(cwd, "deep/nested/file.txt")) == "nested"
  end
end
