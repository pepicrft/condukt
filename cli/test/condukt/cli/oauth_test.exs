defmodule Condukt.CLI.OAuthTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.OAuth

  test "unreserved characters pass through the encoder untouched" do
    assert OAuth.url_encode("abc-DEF_123.~") == "abc-DEF_123.~"
  end

  test "everything else is percent encoded" do
    assert OAuth.url_encode("http://127.0.0.1:12345/oauth/callback/condukt") ==
             "http%3A%2F%2F127.0.0.1%3A12345%2Foauth%2Fcallback%2Fcondukt"
  end

  test "a verifier and its challenge follow RFC 7636" do
    {verifier, challenge} = OAuth.generate_pkce()

    assert String.length(verifier) == 64
    assert verifier =~ ~r/\A[A-Za-z0-9\-._~]+\z/
    assert challenge == Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)
  end

  test "each verifier is distinct" do
    {first, _challenge} = OAuth.generate_pkce()
    {second, _challenge} = OAuth.generate_pkce()

    assert first != second
  end

  test "starting a login returns without waiting for the browser" do
    started_at = System.monotonic_time(:millisecond)
    assert {:ok, login} = OAuth.start_login()

    assert System.monotonic_time(:millisecond) - started_at < 1_000
    assert login.authorize_url =~ "https://openrouter.ai/auth?callback_url=http%3A%2F%2F127.0.0.1%3A"
    assert login.authorize_url =~ "code_challenge_method=S256"

    OAuth.cancel(login)
  end

  test "cancelling a login stops waiting for a callback" do
    assert {:ok, login} = OAuth.start_login()
    OAuth.cancel(login)

    assert {:error, message} = OAuth.await(login, 200)
    assert message =~ "Timed out"
  end

  describe "interpreting a callback request" do
    test "a code is captured" do
      assert {:ok, "abc123"} = OAuth.interpret(request("/oauth/callback/condukt?code=abc123"))
    end

    test "an encoded code is decoded" do
      assert {:ok, "a b/c"} = OAuth.interpret(request("/oauth/callback/condukt?code=a+b%2Fc"))
    end

    test "a provider error is reported" do
      assert {:error, 400, message} =
               OAuth.interpret(request("/oauth/callback/condukt?error=access_denied&error_description=nope"))

      assert message =~ "access_denied"
      assert message =~ "nope"
    end

    test "a callback with no code is rejected" do
      assert {:error, 400, message} = OAuth.interpret(request("/oauth/callback/condukt"))
      assert message =~ "did not include a code"
    end

    test "another path is not the callback" do
      assert {:error, 404, message} = OAuth.interpret(request("/favicon.ico"))
      assert message =~ "Unexpected callback path"
    end

    test "a malformed request is rejected" do
      assert {:error, 400, message} = OAuth.interpret("nonsense\r\n\r\n")
      assert message =~ "Malformed"
    end
  end

  defp request(target), do: "GET #{target} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
end
