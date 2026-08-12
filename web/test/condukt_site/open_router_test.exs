defmodule ConduktSite.OpenRouterTest do
  use ExUnit.Case, async: true

  alias ConduktSite.OpenRouter

  test "authorization uses a unique callback path and a secure challenge" do
    authorization =
      OpenRouter.authorization(fn state -> "https://condukt.test/auth/callback/#{state}" end)

    uri = URI.parse(authorization.url)
    query = URI.decode_query(uri.query)

    assert uri.scheme == "https"
    assert uri.host == "openrouter.ai"

    assert query["callback_url"] ==
             "https://condukt.test/auth/callback/#{authorization.state}"

    assert query["code_challenge_method"] == "S256"

    assert query["code_challenge"] ==
             :crypto.hash(:sha256, authorization.verifier)
             |> Base.url_encode64(padding: false)

    refute authorization.url =~ authorization.verifier
  end

  test "translates the public browser contract to the provider contract" do
    body =
      OpenRouter.completion_body(%{
        "model" => "example/model",
        "messages" => [
          %{"role" => "user", "content" => "hello"},
          %{
            "role" => "assistant",
            "content" => "",
            "toolCalls" => [
              %{"id" => "call-1", "name" => "read_page", "arguments" => "{}"}
            ]
          },
          %{"role" => "tool", "content" => "page", "toolCallId" => "call-1"}
        ],
        "tools" => [
          %{
            "name" => "read_page",
            "description" => "Read the page",
            "parameters" => %{"type" => "object", "properties" => %{}}
          }
        ]
      })

    assert body["model"] == "example/model"

    assert get_in(body, ["messages", Access.at(1), "tool_calls", Access.at(0), "function", "name"]) ==
             "read_page"

    assert get_in(body, ["messages", Access.at(2), "tool_call_id"]) == "call-1"
    assert get_in(body, ["tools", Access.at(0), "function", "name"]) == "read_page"
  end

  test "handles provider error objects without raising" do
    Req.Test.expect(OpenRouter, fn request ->
      request
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{"error" => %{"unexpected" => "shape"}})
    end)

    assert {:error, message} = OpenRouter.exchange_code("code", "verifier")
    assert message == "OpenRouter returned status 429: request failed"
  end
end
