defmodule Glossia.Agent.Tools.EditTest do
  use Glossia.Agent.ToolCase

  alias Glossia.Agent.Tools.Edit

  test "replaces exact text", %{cwd: cwd} do
    path = Path.join(cwd, "edit.txt")
    File.write!(path, "Hello, World!")

    context = %{cwd: cwd, opts: []}

    {:ok, result} =
      Edit.call(
        %{
          "path" => "edit.txt",
          "old_text" => "World",
          "new_text" => "Elixir"
        },
        context
      )

    assert String.contains?(result, "Successfully edited")
    assert File.read!(path) == "Hello, Elixir!"
  end

  test "returns error when text not found", %{cwd: cwd} do
    path = Path.join(cwd, "edit.txt")
    File.write!(path, "Hello, World!")

    context = %{cwd: cwd, opts: []}

    {:error, error} =
      Edit.call(
        %{
          "path" => "edit.txt",
          "old_text" => "Goodbye",
          "new_text" => "Hi"
        },
        context
      )

    assert String.contains?(error, "not found")
  end

  test "replaces only first occurrence", %{cwd: cwd} do
    path = Path.join(cwd, "multi.txt")
    File.write!(path, "foo bar foo bar")

    context = %{cwd: cwd, opts: []}

    {:ok, _result} =
      Edit.call(
        %{
          "path" => "multi.txt",
          "old_text" => "foo",
          "new_text" => "baz"
        },
        context
      )

    assert File.read!(path) == "baz bar foo bar"
  end
end
