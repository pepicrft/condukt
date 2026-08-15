defmodule Condukt.CLI.WorkspaceTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.Workspace

  setup do
    root = Path.join(System.tmp_dir!(), "condukt-workspace-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    {:ok, root: root}
  end

  test "lists files at the root, sorted, without directories", %{root: root} do
    File.write!(Path.join(root, "b.txt"), "b")
    File.write!(Path.join(root, "a.txt"), "a")
    File.mkdir_p!(Path.join(root, "nested"))

    assert {:ok, [first, second]} = Workspace.files(root)
    assert Path.basename(first) == "a.txt"
    assert Path.basename(second) == "b.txt"
  end

  test "reports a missing root", %{root: root} do
    assert {:error, :enoent} = Workspace.files(Path.join(root, "nope"))
  end

  test "reads a file relative to the root", %{root: root} do
    File.write!(Path.join(root, "hello.txt"), "hello, world\n")

    assert {:ok, "hello, world\n"} = Workspace.read(root, "hello.txt")
  end

  test "reads an absolute path", %{root: root} do
    path = Path.join(root, "absolute.txt")
    File.write!(path, "absolute content")

    assert {:ok, "absolute content"} = Workspace.read(root, path)
  end

  test "reports a missing file", %{root: root} do
    assert {:error, message} = Workspace.read(root, "nope.txt")
    assert message =~ "could not read"
  end

  test "truncates a large file", %{root: root} do
    File.write!(Path.join(root, "big.txt"), String.duplicate("x", 60_000))

    assert {:ok, contents} = Workspace.read(root, "big.txt")
    assert String.ends_with?(contents, "... (truncated)")
  end

  test "truncation lands on a character boundary" do
    truncated = Workspace.truncate(String.duplicate("x", 49_999) <> "é", 50_000)

    assert String.valid?(truncated)
    assert String.ends_with?(truncated, "... (truncated)")
  end

  test "output within the budget is untouched" do
    assert Workspace.truncate("short", 50_000) == "short"
  end
end
