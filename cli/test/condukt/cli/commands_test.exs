defmodule Condukt.CLI.CommandsTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.Commands

  test "parses an argument without losing the spaces inside it" do
    assert {:ok, %{kind: :read}, "folder/my file.ex"} = Commands.parse("/read folder/my file.ex")
  end

  test "a command with no argument parses with an empty one" do
    assert {:ok, %{kind: :files}, ""} = Commands.parse("/files")
  end

  test "unknown input does not parse" do
    assert :error = Commands.parse("/teleport")
    assert :error = Commands.parse("not a command")
  end

  test "help is generated from the command catalogue" do
    help = Commands.help_text()
    for command <- Commands.all(), do: assert(help =~ command.usage)
  end

  test "an empty query lists every command in table order" do
    assert Commands.filter("") == Commands.all()
  end

  test "filtering ranks the closest command first" do
    assert [%{name: "files"} | _rest] = Commands.filter("fil")
    assert [%{name: "connect"} | _rest] = Commands.filter("conn")
    assert [%{name: "quit"} | _rest] = Commands.filter("quit")
  end

  test "filtering matches a subsequence, not only a prefix" do
    assert Enum.any?(Commands.filter("wksp"), &(&1.name == "files"))
  end

  test "a query nothing matches filters everything out" do
    assert Commands.filter("zzzz") == []
  end
end
