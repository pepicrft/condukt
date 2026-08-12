defmodule ConduktSiteWeb.CompletionControllerTest do
  use ConduktSiteWeb.ConnCase, async: true

  test "requires an OpenRouter session", %{conn: conn} do
    conn = post(conn, ~p"/api/completions", %{"messages" => [], "tools" => []})
    assert %{"error" => message} = json_response(conn, 401)
    assert message =~ "Log in with OpenRouter"
  end

  test "proxies a provider-neutral request without returning the credential", %{conn: conn} do
    Req.Test.expect(ConduktSite.OpenRouter, fn request ->
      {:ok, body, request} = Plug.Conn.read_body(request)
      body = Jason.decode!(body)

      assert Plug.Conn.get_req_header(request, "authorization") == ["Bearer secret-key"]
      assert body["model"] == "example/model"
      assert get_in(body, ["messages", Access.at(0), "content"]) == "Hello"

      Req.Test.json(request, %{
        "choices" => [%{"message" => %{"role" => "assistant", "content" => "Hello back"}}]
      })
    end)

    conn =
      conn
      |> init_test_session(openrouter_key: "secret-key")
      |> post(~p"/api/completions", %{
        "model" => "example/model",
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "tools" => []
      })

    assert %{"role" => "assistant", "content" => "Hello back"} = json_response(conn, 200)
    refute conn.resp_body =~ "secret-key"
  end

  test "rejects malformed requests before they reach the provider", %{conn: conn} do
    conn =
      conn
      |> init_test_session(openrouter_key: "secret-key")
      |> post(~p"/api/completions", %{"messages" => "not-a-list", "tools" => []})

    assert %{"error" => message} = json_response(conn, 422)
    assert message =~ "messages must be a list"
  end

  test "turns a malformed provider response into a gateway error", %{conn: conn} do
    Req.Test.expect(ConduktSite.OpenRouter, fn request ->
      Req.Test.json(request, %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => "",
              "tool_calls" => [%{"id" => "call-1", "function" => %{}}]
            }
          }
        ]
      })
    end)

    conn =
      conn
      |> init_test_session(openrouter_key: "secret-key")
      |> post(~p"/api/completions", %{
        "messages" => [%{"role" => "user", "content" => "Hello"}],
        "tools" => []
      })

    assert %{"error" => message} = json_response(conn, 502)
    assert message =~ "invalid response"
  end
end
