defmodule Condukt.Tools.BashTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Condukt.Sandbox
  alias Condukt.Tools.Bash

  @moduletag :tmp_dir

  setup :set_mimic_from_context
  setup :verify_on_exit!

  setup %{tmp_dir: tmp_dir} do
    {:ok, sandbox} = Sandbox.new(Sandbox.Local, cwd: tmp_dir)
    %{context: %{sandbox: sandbox, opts: []}}
  end

  test "executes simple command", %{tmp_dir: tmp_dir, context: context} do
    MuonTrap
    |> expect(:cmd, fn "bash", ["-c", "echo hello"], opts ->
      assert opts[:cd] == tmp_dir
      assert opts[:stderr_to_stdout] == true
      assert opts[:timeout] == 120_000
      assert {"TERM", "dumb"} in opts[:env]
      {"hello\n", 0}
    end)

    {:ok, result} = Bash.call(%{"command" => "echo hello"}, context)

    assert String.contains?(result, "hello")
  end

  test "passes session secrets as environment variables", %{tmp_dir: tmp_dir, context: context} do
    context = Map.put(context, :secrets, %Condukt.Secrets{env: [{"GH_TOKEN", "secret-token"}]})

    MuonTrap
    |> expect(:cmd, fn "bash", ["-c", "echo $GH_TOKEN"], opts ->
      assert opts[:cd] == tmp_dir
      assert {"GH_TOKEN", "secret-token"} in opts[:env]
      {"secret-token\n", 0}
    end)

    {:ok, result} = Bash.call(%{"command" => "echo $GH_TOKEN"}, context)

    assert String.contains?(result, "secret-token")
  end

  test "captures stderr", %{tmp_dir: tmp_dir, context: context} do
    MuonTrap
    |> expect(:cmd, fn "bash", ["-c", "echo error >&2"], opts ->
      assert opts[:cd] == tmp_dir
      {"error\n", 0}
    end)

    {:ok, result} = Bash.call(%{"command" => "echo error >&2"}, context)

    assert String.contains?(result, "error")
  end

  test "returns exit code for failures", %{tmp_dir: tmp_dir, context: context} do
    MuonTrap
    |> expect(:cmd, fn "bash", ["-c", "exit 42"], opts ->
      assert opts[:cd] == tmp_dir
      {"", 42}
    end)

    {:ok, result} = Bash.call(%{"command" => "exit 42"}, context)

    assert String.contains?(result, "exit code: 42")
  end

  test "respects cwd", %{tmp_dir: tmp_dir, context: context} do
    MuonTrap
    |> expect(:cmd, fn "bash", ["-c", "pwd"], opts ->
      assert opts[:cd] == tmp_dir
      {"#{tmp_dir}\n", 0}
    end)

    {:ok, result} = Bash.call(%{"command" => "pwd"}, context)

    assert String.contains?(result, tmp_dir)
  end

  test "accepts cwd argument relative to context cwd", %{tmp_dir: tmp_dir, context: context} do
    nested_dir = Path.join(tmp_dir, "nested")
    File.mkdir_p!(nested_dir)

    MuonTrap
    |> expect(:cmd, fn "bash", ["-c", "pwd"], opts ->
      assert opts[:cd] == nested_dir
      {"#{nested_dir}\n", 0}
    end)

    {:ok, result} = Bash.call(%{"command" => "pwd", "cwd" => "nested"}, context)

    assert String.contains?(result, nested_dir)
  end

  test "returns runner errors as command failures", %{context: context} do
    MuonTrap
    |> expect(:cmd, fn "bash", ["-c", "pwd"], _opts ->
      raise ErlangError, original: :enoent
    end)

    assert {:error, "Command failed: \"Erlang error: :enoent\""} =
             Bash.call(%{"command" => "pwd"}, context)
  end
end
