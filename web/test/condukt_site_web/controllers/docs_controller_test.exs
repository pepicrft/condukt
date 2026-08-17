defmodule ConduktSiteWeb.DocsControllerTest do
  use ConduktSiteWeb.ConnCase, async: true

  test "GET /docs presents the two documentation journeys", %{conn: conn} do
    body = conn |> get(~p"/docs") |> html_response(200)

    assert body =~ "Build an agent with Condukt"
    assert body =~ "Build an agent"
    assert body =~ "Contain the work"
    assert body =~ ~s(id="docs-sidebar")
    refute body =~ ~s(id="docs-toc")
    assert body =~ ~s(data-surface="docs")
    assert body =~ ~s(href="/docs/framework")
    assert body =~ ~s(href="/docs/framework/elixir/sandbox")
    assert body =~ ~s(<noora-icon name="brand_github")
  end

  test "a documentation page renders Markdown and its outline", %{conn: conn} do
    body = conn |> get(~p"/docs/framework/elixir/getting-started") |> html_response(200)

    assert body =~ ~s(id="docs-toc")
    assert body =~ ~s(class="code-window")
    assert body =~ "as Markdown"
    assert body =~ "data-selected"
  end

  test "GET /docs-markdown returns the source document", %{conn: conn} do
    conn = get(conn, ~p"/docs-markdown/framework/elixir/getting-started")

    assert get_resp_header(conn, "content-type") == ["text/markdown; charset=utf-8"]
    assert response(conn, 200) =~ "#"
  end

  test "section indexes link to their real Markdown source", %{conn: conn} do
    body = conn |> get(~p"/docs/framework") |> html_response(200)

    assert body =~ "https://github.com/tuist/condukt/edit/main/web/priv/docs/framework/index.md"
  end

  test "unknown documentation pages return a documentation 404", %{conn: conn} do
    body = conn |> get(~p"/docs/framework/not-real") |> html_response(404)

    assert body =~ "Page not found"
    assert body =~ "/docs/framework/not-real"
  end
end
