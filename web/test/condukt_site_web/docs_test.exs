defmodule ConduktSiteWeb.DocsTest do
  use ExUnit.Case, async: false

  alias ConduktSiteWeb.Docs
  alias ConduktSiteWeb.Docs.Markdown
  alias ConduktSiteWeb.Docs.Navigation

  test "resolves a Markdown page and rejects traversal" do
    assert {:ok, page} = Docs.get_page(["guide", "getting-started"])
    assert page.title == "Install and connect"
    assert page.markdown =~ "mise use -g github:tuist/condukt"
    assert page.source_path == "guide/getting-started.md"

    assert {:ok, index_page} = Docs.get_page(["guide"])
    assert index_page.source_path == "guide/index.md"

    assert :error = Docs.source_path(["..", "README"])
    assert :error = Docs.source_path(["guide/getting-started"])
  end

  test "routes pages into persona-based navigation" do
    assert Navigation.tab_for_slug("/docs") == :home
    assert Navigation.tab_for_slug("/docs/guide/terminal") == :use_condukt
    assert Navigation.tab_for_slug("/docs/guide/editor") == :use_condukt
    assert Navigation.tab_for_slug("/docs/reference/command-line") == :use_condukt
    assert Navigation.tab_for_slug("/docs/guide/browser") == :build_agents
    assert Navigation.tab_for_slug("/docs/reference/tools") == :build_agents
    assert Navigation.tab_for_slug("/docs/reference/internals") == :build_agents
  end

  test "renders headings, links, and copyable code windows" do
    page =
      Markdown.render("""
      # Example

      ## Run it

      [Read the guide](/guide/getting-started).

      ```sh
      condukt --help
      ```
      """)

    assert page.title == "Example"
    assert page.headings == [%{level: 2, id: "run-it", text: "Run it"}]
    assert page.html =~ ~s(data-part="heading-anchor")
    assert page.html =~ ~s(href="/docs/guide/getting-started")
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
      source_path
      |> File.read!()
      |> then(&Regex.scan(~r/\]\(\/(guide|reference)(?:\/([^\s)#]+))?(?:#[^\s)]*)?\)/, &1))
      |> Enum.each(fn [_match, section, rest] ->
        segments = [section | String.split(rest, "/", trim: true)]

        assert {:ok, _path} = Docs.source_path(segments),
               "#{Path.relative_to(source_path, Docs.root())} links to missing /#{Enum.join(segments, "/")}"
      end)
    end)
  end
end
