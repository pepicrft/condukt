defmodule ConduktSiteWeb.PageControllerTest do
  use ConduktSiteWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    body = html_response(conn, 200)
    assert body =~ "Agents you can"
    assert body =~ "Elixir framework · Hex package · MIT licensed"
    assert body =~ ~s(<noora-icon name="brand_github")
    assert body =~ ~s(href="/docs">Docs</a>)
  end

  # The framework is what this page sells, so the Hex dependency is the install
  # and the coding agent follows it rather than leading.
  test "GET / leads with the framework", %{conn: conn} do
    body = conn |> get(~p"/") |> html_response(200)

    # The dependency line is an attribute, so its quotes arrive escaped.
    assert body =~ "{:condukt,"
    assert body =~ "mise use -g github:tuist/condukt"

    hex = :binary.match(body, "{:condukt,") |> elem(0)
    binary = :binary.match(body, "mise use -g") |> elem(0)
    assert hex < binary

    # The differentiated capabilities, not the loop.
    assert body =~ "sandbox"
    assert body =~ "network"
  end

  # The terminal is a LiveView embedded in this page, so the controller's job
  # is to mount it. What it renders is TerminalLive's own test.
  test "embeds the terminal as a LiveView", %{conn: conn} do
    body = conn |> get(~p"/") |> html_response(200)

    assert body =~ ~s(id="terminal")
    assert body =~ "data-phx-session="
    assert body =~ ~s(phx-hook="ConduktTerminal")
    assert body =~ "Log in with OpenRouter"
  end

  test "the terminal offers the composer once a session is connected", %{conn: conn} do
    body =
      conn
      |> init_test_session(openrouter_key: "encrypted-by-the-session")
      |> get(~p"/")
      |> html_response(200)

    assert body =~ ~s(id="agent-prompt")
    refute body =~ "Log in with OpenRouter"
    refute body =~ "encrypted-by-the-session"
  end
end
