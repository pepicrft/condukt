defmodule ConduktSiteWeb.DocsControllerTest do
  use ConduktSiteWeb.ConnCase, async: true

  test "GET /docs presents the two documentation journeys", %{conn: conn} do
    body = conn |> get(~p"/docs") |> html_response(200)

    assert body =~ "What do you want to do with Condukt?"
    assert body =~ "Build an agent"
    assert body =~ "Use the terminal agent"
    assert body =~ ~s(id="docs-sidebar")
    refute body =~ ~s(id="docs-toc")
    assert body =~ ~s(data-surface="docs")
    assert body =~ ~s(href="/docs/cli")
    assert body =~ ~s(href="/docs/framework")
    assert body =~ ~s(<noora-icon name="brand_github")
  end

  test "GET /docs/guide/getting-started renders Markdown and its outline", %{conn: conn} do
    body = conn |> get(~p"/docs/cli/getting-started") |> html_response(200)

    assert body =~ "Install with mise"
    assert body =~ ~s(id="docs-toc")
    assert body =~ ~s(class="code-window")
    assert body =~ "as Markdown"
    assert body =~ "data-selected"
    assert body =~ "Install and connect"
  end

  test "GET /docs-markdown returns the source document", %{conn: conn} do
    conn = get(conn, ~p"/docs-markdown/cli/getting-started")

    assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
    assert response(conn, 200) =~ "# Install and connect"
  end

  test "section indexes link to their real Markdown source", %{conn: conn} do
    body = conn |> get(~p"/docs/cli") |> html_response(200)

    assert body =~ "https://github.com/tuist/condukt/edit/main/web/priv/docs/cli/index.md"
  end

  test "unknown documentation pages return a documentation 404", %{conn: conn} do
    body = conn |> get(~p"/docs/cli/not-real") |> html_response(404)

    assert body =~ "Page not found"
    assert body =~ "/docs/cli/not-real"
  end
end
