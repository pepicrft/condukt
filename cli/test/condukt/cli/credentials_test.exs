defmodule Condukt.CLI.CredentialsTest do
  use ExUnit.Case, async: true

  alias Condukt.CLI.Credentials

  setup do
    directory = Path.join(System.tmp_dir!(), "condukt-credentials-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(directory) end)
    {:ok, store: Credentials.new(directory), directory: directory}
  end

  test "a store round-trips and deletes credentials", %{store: store} do
    assert {:ok, nil} = Credentials.load(store)
    assert :ok = Credentials.save(store, "test credential")
    assert {:ok, "test credential"} = Credentials.load(store)
    assert :ok = Credentials.delete(store)
    assert {:ok, nil} = Credentials.load(store)
  end

  test "deleting an absent credential succeeds", %{store: store} do
    assert :ok = Credentials.delete(store)
  end

  test "saving replaces an existing credential", %{store: store} do
    :ok = Credentials.save(store, "first")
    :ok = Credentials.save(store, "second")
    assert {:ok, "second"} = Credentials.load(store)
  end

  test "save_if_missing does not overwrite", %{store: store} do
    assert {:ok, true} = Credentials.save_if_missing(store, "first")
    assert {:ok, false} = Credentials.save_if_missing(store, "second")
    assert {:ok, "first"} = Credentials.load(store)
  end

  test "the credential file is not world readable", %{store: store, directory: directory} do
    :ok = Credentials.save(store, "secret")
    {:ok, %File.Stat{mode: mode}} = File.stat(Path.join(directory, "openrouter.key"))

    assert Bitwise.band(mode, 0o077) == 0
  end

  test "a custom directory is preserved" do
    assert Credentials.directory(Credentials.new("/tmp/condukt-credentials")) == "/tmp/condukt-credentials"
  end

  describe "resolving the directory" do
    test "an explicit directory wins" do
      env = fake_env(%{"CONDUKT_CREDENTIAL_DIR" => "/explicit"})
      assert {:ok, store} = Credentials.from_environment(env)
      assert Credentials.directory(store) == "/explicit"
    end

    test "the configuration home is used next" do
      env = fake_env(%{"XDG_CONFIG_HOME" => "/xdg"})
      assert {:ok, store} = Credentials.from_environment(env)
      assert Credentials.directory(store) == "/xdg/condukt"
    end

    test "the home directory is the fallback" do
      env = fake_env(%{"HOME" => "/home/person"})
      assert {:ok, store} = Credentials.from_environment(env)
      assert Credentials.directory(store) == "/home/person/.config/condukt"
    end

    test "without a home directory it fails rather than guessing" do
      assert {:error, :home_directory_unknown} = Credentials.from_environment(fake_env(%{}))
    end
  end

  describe "importing from Pi" do
    test "copies the access credential when Condukt has none", %{directory: directory} do
      source = write_pi_auth(~s({"openrouter": {"access": "sk-or-v1-from-pi"}}))
      env = fake_env(%{"CONDUKT_CREDENTIAL_DIR" => directory, "CONDUKT_PI_AUTH_FILE" => source})

      assert {:ok, true} = Credentials.import_pi_credential(env)
      assert {:ok, "sk-or-v1-from-pi"} = Credentials.load(Credentials.new(directory))
    end

    test "leaves an existing credential alone", %{store: store, directory: directory} do
      :ok = Credentials.save(store, "already here")
      source = write_pi_auth(~s({"openrouter": {"access": "sk-or-v1-from-pi"}}))
      env = fake_env(%{"CONDUKT_CREDENTIAL_DIR" => directory, "CONDUKT_PI_AUTH_FILE" => source})

      assert {:ok, false} = Credentials.import_pi_credential(env)
      assert {:ok, "already here"} = Credentials.load(store)
    end

    test "reports a missing source file", %{directory: directory} do
      env =
        fake_env(%{"CONDUKT_CREDENTIAL_DIR" => directory, "CONDUKT_PI_AUTH_FILE" => "/nope/auth.json"})

      assert {:error, {:pi_credential_missing, "/nope/auth.json"}} = Credentials.import_pi_credential(env)
    end

    test "reports a source without an OpenRouter credential", %{directory: directory} do
      source = write_pi_auth(~s({"anthropic": {"access": "x"}}))
      env = fake_env(%{"CONDUKT_CREDENTIAL_DIR" => directory, "CONDUKT_PI_AUTH_FILE" => source})

      assert {:error, :pi_openrouter_credential_missing} = Credentials.import_pi_credential(env)
    end

    test "reports an unreadable source", %{directory: directory} do
      source = write_pi_auth("not json")
      env = fake_env(%{"CONDUKT_CREDENTIAL_DIR" => directory, "CONDUKT_PI_AUTH_FILE" => source})

      assert {:error, :pi_credential_unreadable} = Credentials.import_pi_credential(env)
    end
  end

  defp fake_env(values), do: fn name -> Map.get(values, name) end

  defp write_pi_auth(contents) do
    path = Path.join(System.tmp_dir!(), "condukt-pi-auth-#{System.unique_integer([:positive])}.json")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
