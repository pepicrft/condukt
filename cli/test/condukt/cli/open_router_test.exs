defmodule Condukt.CLI.OpenRouterTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.MockServer
  alias Condukt.CLI.OpenRouter

  test "the model is the one the interface reports" do
    assert OpenRouter.req_llm_model() == "openrouter:" <> OpenRouter.model()
  end

  test "validation accepts a 2xx response and sends the key" do
    {base_url, _port} = MockServer.start(200, ~s({"data":{"label":"test-key"}}))

    assert :ok = OpenRouter.validate("sk-or-v1-test", base_url: base_url)
    assert String.downcase(MockServer.received_request()) =~ "authorization: bearer sk-or-v1-test"
  end

  test "validation rejects a 401 with a hint to re-authenticate" do
    {base_url, _port} = MockServer.start(401, ~s({"error":{"message":"User not found.","code":401}}))

    assert {:error, message} = OpenRouter.validate("sk-or-v1-stale", base_url: base_url)
    assert message =~ "re-authenticate"
  end

  test "validation surfaces other status codes" do
    {base_url, _port} = MockServer.start(500, ~s({"error":"oops"}))

    assert {:error, message} = OpenRouter.validate("sk-or-v1-test", base_url: base_url)
    assert message =~ "500"
  end

  test "validation reports an unreachable service" do
    # Port 1 on loopback refuses connections, which is the transport failure a
    # user sees when they are offline.
    assert {:error, message} = OpenRouter.validate("sk-or-v1-test", base_url: "http://127.0.0.1:1")
    assert message =~ "Could not reach OpenRouter"
  end

  describe "turn errors" do
    test "a rejected key points at re-authentication" do
      assert OpenRouter.describe_turn_error("unexpected status 401") =~ "re-authenticate"
    end

    test "a timeout is named as one" do
      assert OpenRouter.describe_turn_error("request timeout") =~ "timed out"
    end

    test "anything else passes through" do
      assert OpenRouter.describe_turn_error("upstream is on fire") == "upstream is on fire"
    end
  end
end
