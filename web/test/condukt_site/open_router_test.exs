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
