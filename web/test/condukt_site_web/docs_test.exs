defmodule ConduktSiteWeb.DocsTest do
  # The docs cache is shared and read-through, and every assertion here reads.
  # Concurrent reads of an idempotent cache need no serialising.
  use ExUnit.Case, async: true

  alias ConduktSiteWeb.Docs
  alias ConduktSiteWeb.Docs.Markdown
  alias ConduktSiteWeb.Docs.Navigation

  test "resolves a Markdown page and rejects traversal" do
    assert {:ok, page} = Docs.get_page(["cli", "getting-started"])
    assert page.title == "Install and connect"
    assert page.markdown =~ "mise use -g"
    assert page.source_path == "cli/getting-started.md"

    assert {:ok, index_page} = Docs.get_page(["cli"])
    assert index_page.source_path == "cli/index.md"

    assert {:ok, elixir_page} = Docs.get_page(["framework", "elixir", "tools"])
    assert elixir_page.source_path == "framework/elixir/tools.md"

    assert :error = Docs.source_path(["..", "README"])
    assert :error = Docs.source_path(["cli/getting-started"])
  end

  test "routes pages into persona-based navigation" do
    assert Navigation.tab_for_slug("/docs") == :home
    assert Navigation.tab_for_slug("/docs/cli") == :use_condukt
    assert Navigation.tab_for_slug("/docs/cli/terminal") == :use_condukt
    assert Navigation.tab_for_slug("/docs/cli/command-line") == :use_condukt
    assert Navigation.tab_for_slug("/docs/framework") == :build_agents
    assert Navigation.tab_for_slug("/docs/framework/elixir/tools") == :build_agents
    assert Navigation.tab_for_slug("/docs/framework/rust/browser") == :build_agents
  end

  test "renders headings, links, and copyable code windows" do
    page =
      Markdown.render("""
      # Example

      ## Run it

      [Read the guide](/cli/getting-started).

      ```sh
      condukt --help
      ```
      """)

    assert page.title == "Example"
    assert page.headings == [%{level: 2, id: "run-it", text: "Run it"}]
    assert page.html =~ ~s(data-part="heading-anchor")
    assert page.html =~ ~s(href="/docs/cli/getting-started")
    assert page.html =~ ~s(class="code-window")
    assert page.html =~ ~s(<template data-part="copy-source">condukt --help</template>)
  end

  test "does not render raw HTML from Markdown" do
    page = Markdown.render("# Safe\n\n<script>alert('unsafe')</script>\n")

    refute page.html =~ "<script"
    refute page.html =~ "alert('unsafe')"
  end

  test "internal documentation links resolve to source pages" do
    Docs.root()
    |> Path.join("**/*.md")
    |> Path.wildcard()
    |> Enum.each(fn source_path ->
      relative = Path.relative_to(source_path, Docs.root())
      source = File.read!(source_path)

      source
      |> then(&Regex.scan(~r/\]\(\/(cli|framework)(?:\/([^\s)#]+))?(?:#[^\s)]*)?\)/, &1))
      |> Enum.each(fn
        [_match, section] ->
          assert_page(relative, [section])

        [_match, section, rest] ->
          assert_page(relative, [section | String.split(rest, "/", trim: true)])
      end)

      source
      |> then(&Regex.scan(~r/\]\(([a-z0-9-]+)\.md(?:#[^\s)]*)?\)/, &1))
      |> Enum.each(fn [_match, sibling] ->
        directory = relative |> Path.dirname() |> Path.split() |> Enum.reject(&(&1 == "."))
        assert_page(relative, directory ++ [sibling])
      end)
    end)
  end

  test "navigation only points at pages that exist" do
    [:home, :use_condukt, :build_agents]
    |> Enum.flat_map(&Navigation.tree_for_tab/1)
    |> Enum.flat_map(& &1.items)
    |> Enum.each(fn item ->
      segments = item.slug |> String.trim_leading("/docs/") |> String.split("/", trim: true)

      assert {:ok, _path} = Docs.source_path(segments),
             "navigation item #{item.label} points at missing #{item.slug}"
    end)
  end

  test "relative Markdown links resolve against the directory of the page" do
    page =
      Markdown.render(
        "# Tools\n\nSee [the sandbox](sandbox.md#custom) and the [overview](index.md).\n",
        "/docs/framework/elixir"
      )

    assert page.html =~ ~s(href="/docs/framework/elixir/sandbox#custom")
    assert page.html =~ ~s(href="/docs/framework/elixir")
  end

  defp assert_page(source, segments) do
    assert {:ok, _path} = Docs.source_path(segments),
           "#{source} links to missing /docs/#{Enum.join(segments, "/")}"
  end
end
