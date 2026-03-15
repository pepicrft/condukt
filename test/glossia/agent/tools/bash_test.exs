defmodule Glossia.Agent.Tools.BashTest do
  use ExUnit.Case, async: true

  alias Glossia.Agent.Tools.Bash

  @moduletag :tmp_dir

  test "executes simple command", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "echo hello"}, context)

    assert String.contains?(result, "hello")
  end

  test "captures stderr", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "echo error >&2"}, context)

    assert String.contains?(result, "error")
  end

  test "returns exit code for failures", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "exit 42"}, context)

    assert String.contains?(result, "exit code: 42")
  end

  test "respects cwd", %{tmp_dir: tmp_dir} do
    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "pwd"}, context)

    assert String.contains?(result, tmp_dir)
  end

  test "accepts cwd argument relative to context cwd", %{tmp_dir: tmp_dir} do
    nested_dir = Path.join(tmp_dir, "nested")
    File.mkdir_p!(nested_dir)

    context = %{cwd: tmp_dir, opts: []}
    {:ok, result} = Bash.call(%{"command" => "pwd", "cwd" => "nested"}, context)

    assert String.contains?(result, nested_dir)
  end

  test "runs commands through nix shell when packages are requested", %{tmp_dir: tmp_dir} do
    parent = self()

    context = %{
      cwd: tmp_dir,
      opts: [
        runner: fn executable, args, cwd, timeout, env ->
          send(parent, {:invocation, executable, args, cwd, timeout, env})
          {:ok, "ok", 0}
        end
      ]
    }

    {:ok, result} =
      Bash.call(
        %{
          "command" => "jq --version",
          "packages" => ["jq", "nixpkgs#ripgrep", ".#custom_tool"]
        },
        context
      )

    assert result == "ok"

    assert_receive {:invocation, "nix", args, ^tmp_dir, 120_000, env}

    assert args == [
             "shell",
             "nixpkgs#jq",
             "nixpkgs#ripgrep",
             ".#custom_tool",
             "--command",
             "bash",
             "-c",
             "jq --version"
           ]

    assert {"TERM", "dumb"} in env
  end

  test "returns a helpful error when nix is unavailable", %{tmp_dir: tmp_dir} do
    context = %{
      cwd: tmp_dir,
      opts: [nix_executable: Path.join(tmp_dir, "missing-nix")]
    }

    {:error, error} =
      Bash.call(
        %{
          "command" => "jq --version",
          "packages" => ["jq"]
        },
        context
      )

    assert String.contains?(error, "Nix is required when packages are specified")
  end
end
