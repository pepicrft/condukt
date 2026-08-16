defmodule ConduktSiteWeb.PageControllerTest do
  use ConduktSiteWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    assert body =~ "One agent."
    assert body =~ "Every surface."
    assert body =~ "Coding agent · Framework · MIT licensed"
    assert body =~ "Coding agent"
    assert body =~ "Framework"
    assert body =~ ~s(<noora-icon name="brand_github")
    assert body =~ ~s(href="/docs">Docs</a>)
    assert body =~ "condukt-browser-agent"
    assert body =~ ~s(connect-url="/auth/openrouter?)
    assert body =~ "condukt-install-command"
    assert body =~ "mise use -g github:tuist/condukt"
    refute body =~ ~s(<condukt-browser-agent connected)
    refute body =~ "noora-card"
  end

  test "renders the browser agent after an OpenRouter session is connected", %{conn: conn} do
    conn = conn |> init_test_session(openrouter_key: "encrypted-by-the-session") |> get(~p"/")
    body = html_response(conn, 200)
    assert body =~ ~s(<condukt-browser-agent)
    assert body =~ "connected"
    assert body =~ ~s(provider="OpenRouter")
    assert body =~ ~s(model="openrouter/auto")
    assert body =~ ~s(inference-endpoint="/api/completions")
    refute body =~ "encrypted-by-the-session"
  end
end
