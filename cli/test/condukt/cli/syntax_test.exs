defmodule Condukt.CLI.SyntaxTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.Syntax

  test "highlights a fenced code block" do
    rendered = Syntax.highlight_markdown("```elixir\ndef main, do: \"hi\"\n```\n")

    assert rendered =~ "\e["
    assert rendered =~ "main"
    assert rendered =~ "```elixir"
  end

  test "colours diff additions and removals" do
    rendered = Syntax.highlight_markdown("```diff\n-old\n+new\n```\n")

    assert rendered =~ "\e[31m-old"
    assert rendered =~ "\e[32m+new"
  end

  test "colours diff headers" do
    rendered = Syntax.highlight_diff("--- a/file\n+++ b/file\n@@ -1 +1 @@")

    assert rendered =~ "\e[36m--- a/file"
    assert rendered =~ "\e[36m@@ -1 +1 @@"
  end

  test "leaves prose alone" do
    prose = "A sentence with # and -- in it.\n\nAnother paragraph.\n"

    assert Syntax.highlight_markdown(prose) == prose
  end

  test "an unterminated fence is still highlighted" do
    rendered = Syntax.highlight_markdown("```diff\n+added")

    assert rendered =~ "\e[32m+added"
  end

  test "a comment marker inside a string is not a comment" do
    rendered = Syntax.highlight_block(~s(url = "https://example.com"), "elixir")

    assert rendered =~ "\e[33m\"https://example.com\"\e[0m"
  end

  test "trailing comments are dimmed" do
    rendered = Syntax.highlight_block("value = 1 # a note", "elixir")

    assert rendered =~ "\e[2;37m# a note"
    assert rendered =~ "\e[35m1\e[0m"
  end

  test "keywords are picked out" do
    rendered = Syntax.highlight_block("def run do", "elixir")

    assert rendered =~ "\e[36mdef\e[0m"
    assert rendered =~ "\e[36mdo\e[0m"
  end
end
