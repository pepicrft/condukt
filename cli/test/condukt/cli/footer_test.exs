defmodule Condukt.CLI.FooterTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.Footer

  defp text(%Footer{} = footer, width) do
    footer |> Footer.lines(width) |> Enum.map_join("\n", fn line -> Enum.map_join(line.spans, & &1.content) end)
  end

  test "shows the worktree and its branch" do
    footer = Footer.apply_refresh(Footer.new("/work/project"), %{branch: "main"})

    assert text(footer, 80) =~ "/work/project (main)"
  end

  test "a detached head is named rather than left blank" do
    assert text(Footer.new("/work/project"), 80) =~ "(detached)"
  end

  test "the model is anchored on the right" do
    line = Footer.new("/work/project") |> Footer.lines(80) |> List.first()

    assert List.last(line.spans).content =~ "(openrouter)"
    assert line.spans |> Enum.map_join(& &1.content) |> String.length() == 80
  end

  test "a narrow terminal drops the right-hand side rather than wrapping" do
    rendered = text(Footer.new("/work/project"), 12)

    assert String.length(rendered) <= 12
    refute rendered =~ "openrouter"
  end

  test "check counts are summarized" do
    footer =
      Footer.apply_refresh(Footer.new("/work/project"), %{
        branch: "topic",
        checks: %{passing: 3, failing: 1, pending: 2}
      })

    rendered = text(footer, 120)
    assert rendered =~ "CI: ✓ 3 passing, ✗ 1 failing, ⋯ 2 pending"
  end

  test "empty check counts leave the segment out" do
    assert Footer.format_checks(%{passing: 0, failing: 0, pending: 0}) == nil
    assert Footer.format_checks(nil) == nil
  end

  test "checks are tallied by conclusion" do
    checks = [
      %{"conclusion" => "SUCCESS"},
      %{"conclusion" => "FAILURE"},
      %{"conclusion" => "TIMED_OUT"},
      %{"conclusion" => nil}
    ]

    assert Footer.tally(checks) == %{passing: 1, failing: 2, pending: 1}
  end

  describe "shortening a path" do
    test "the home directory becomes a tilde" do
      assert Footer.shorten_path("/home/person/code", "/home/person") == "~/code"
    end

    test "a deep path keeps only its last components" do
      assert Footer.shorten_path("/a/b/c/d/e/f", nil) == "…/e/f"
    end

    test "a path outside the home directory is left alone" do
      assert Footer.shorten_path("/opt/tool", "/home/person") == "/opt/tool"
    end
  end
end
