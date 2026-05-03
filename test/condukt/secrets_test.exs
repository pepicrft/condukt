defmodule Condukt.SecretsTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Condukt.{Message, Secrets}
  alias Condukt.Secrets.Providers.OnePassword

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "resolves static and environment provider secrets" do
    System.put_env("CONDUKT_TEST_TOKEN", "env-token")

    on_exit(fn ->
      System.delete_env("CONDUKT_TEST_TOKEN")
    end)

    assert {:ok, secrets} =
             Secrets.resolve(
               API_TOKEN: {:static, "static-token"},
               ENV_TOKEN: {:env, "CONDUKT_TEST_TOKEN"}
             )

    assert {"API_TOKEN", "static-token"} in secrets.env
    assert {"ENV_TOKEN", "env-token"} in secrets.env
  end

  test "later declarations replace earlier declarations" do
    assert {:ok, secrets} =
             Secrets.resolve(
               TOKEN: {:static, "old"},
               TOKEN: {:static, "new"}
             )

    assert secrets.env == [{"TOKEN", "new"}]
  end

  test "rejects invalid environment names" do
    assert {:error, {:invalid_secret_env_name, "not-valid-name"}} =
             Secrets.resolve(%{"not-valid-name" => {:static, "value"}})
  end

  test "redacts resolved secrets from messages and nested tool results" do
    {:ok, secrets} = Secrets.resolve(API_TOKEN: {:static, "secret-token"})

    messages = [
      Message.user("use secret-token"),
      Message.tool_result("call-1", %{"token" => "secret-token", "list" => ["secret-token"]})
    ]

    assert [
             %Message{content: "use [REDACTED:API_TOKEN]"},
             %Message{content: %{"token" => "[REDACTED:API_TOKEN]", "list" => ["[REDACTED:API_TOKEN]"]}}
           ] = Secrets.redact_messages(secrets, messages)
  end

  test "does not redact very short values" do
    {:ok, secrets} = Secrets.resolve(PIN: {:static, "123"})

    assert "pin 123" == Secrets.redact_text(secrets, "pin 123")
  end

  test "one password provider loads a secret reference with op read" do
    MuonTrap
    |> expect(:cmd, fn "op", ["read", "op://Engineering/GitHub/token", "--account", "acme"], opts ->
      assert opts[:stderr_to_stdout] == true
      assert opts[:timeout] == 5_000
      assert {"OP_SERVICE_ACCOUNT_TOKEN", "service-token"} in opts[:env]
      {"github-token\n", 0}
    end)

    assert {:ok, "github-token"} =
             OnePassword.load(
               ref: "op://Engineering/GitHub/token",
               account: "acme",
               timeout: 5_000,
               env: [OP_SERVICE_ACCOUNT_TOKEN: "service-token"]
             )
  end
end
