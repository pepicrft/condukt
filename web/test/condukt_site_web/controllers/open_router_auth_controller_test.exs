defmodule ConduktSiteWeb.OpenRouterAuthControllerTest do
  use ConduktSiteWeb.ConnCase, async: true

  test "starts authorization without exposing the verifier", %{conn: conn} do
    conn = get(conn, ~p"/auth/openrouter?#{%{return_to: "/#agent"}}")
    flow = get_session(conn, :openrouter_flow)
    location = get_resp_header(conn, "location") |> List.first()

    assert redirected_to(conn, 302) =~ "https://openrouter.ai/auth?"
    assert flow["return_to"] == "/#agent"
    assert flow["state"]
    assert flow["verifier"]
    refute location =~ flow["verifier"]
    assert location =~ URI.encode_www_form(flow["state"])
  end

  test "does not allow an external return location", %{conn: conn} do
    conn = get(conn, ~p"/auth/openrouter?#{%{return_to: "https://attacker.test"}}")
    assert get_session(conn, :openrouter_flow)["return_to"] == "/"
  end

  test "rejects network-path and backslash return locations", %{conn: conn} do
    for return_to <- ["//attacker.test/path", "/\\attacker.test/path"] do
      conn = get(conn, ~p"/auth/openrouter?#{%{return_to: return_to}}")
      assert get_session(conn, :openrouter_flow)["return_to"] == "/"
    end
  end

  test "rejects a callback whose path state does not match the session", %{conn: conn} do
    conn =
      conn
      |> init_test_session(
        openrouter_flow: %{
          "state" => "expected",
          "verifier" => "secret",
          "return_to" => "/"
        }
      )
      |> get(~p"/auth/openrouter/callback/different?code=code")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    assert get_session(conn, :openrouter_flow) == nil
  end

  test "stores the exchanged key and returns to the agent", %{conn: conn} do
    Req.Test.expect(ConduktSite.OpenRouter, fn request ->
      {:ok, body, request} = Plug.Conn.read_body(request)
      body = Jason.decode!(body)

      assert request.request_path == "/api/v1/auth/keys"
      assert body["code"] == "temporary-code"
      assert body["code_verifier"] == "secret-verifier"

      Req.Test.json(request, %{"key" => "private-openrouter-key"})
    end)

    conn =
      conn
      |> init_test_session(
        openrouter_flow: %{
          "state" => "expected-state",
          "verifier" => "secret-verifier",
          "return_to" => "/#agent"
        }
      )
      |> get(~p"/auth/openrouter/callback/expected-state?code=temporary-code")

    assert redirected_to(conn) == "/#agent"
    assert get_session(conn, :openrouter_key) == "private-openrouter-key"
    assert get_session(conn, :openrouter_flow) == nil
  end
end
