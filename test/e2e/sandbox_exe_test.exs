defmodule Condukt.E2E.SandboxExeTest do
  @moduledoc """
  End-to-end test that runs a simple agent workflow inside an exe.dev sandbox.

  Requires EXE_DEV_TOKEN environment variable.
  Run with: mix test test/e2e/sandbox_exe_test.exs --include e2e
  """
  use ExUnit.Case, async: false

  @moduletag :e2e

  @tag timeout: to_timeout(minute: 10)
  test "Terrarium.replicate starts a peer node in exe.dev sandbox" do
    token = System.fetch_env!("EXE_DEV_TOKEN")

    {:ok, sandbox} = Terrarium.create(Terrarium.Providers.Exe, token: token)

    try do
      {:ok, pid, _node} = Terrarium.replicate(sandbox)

      try do
        # Execute a command on the remote node via :peer.call
        output = :peer.call(pid, :os, :cmd, [~c"echo hello_from_sandbox"]) |> List.to_string()
        assert String.trim(output) == "hello_from_sandbox"

        # Verify OTP version matches
        remote_otp = :peer.call(pid, :erlang, :system_info, [:otp_release]) |> List.to_string()
        local_otp = :erlang.system_info(:otp_release) |> List.to_string()
        assert remote_otp == local_otp
      after
        Terrarium.stop_replica(pid)
      end
    after
      Terrarium.destroy(sandbox)
    end
  end

  @tag timeout: to_timeout(minute: 10)
  test "Condukt.Sandbox provisions and executes tools remotely" do
    token = System.fetch_env!("EXE_DEV_TOKEN")

    sandbox_config = %{
      provider: Terrarium.Providers.Exe,
      provider_opts: [token: token]
    }

    {:ok, sandbox_pid} = Condukt.Sandbox.start_link(sandbox_config)

    try do
      # Execute a tool on the remote node via Condukt.Sandbox
      context = %{agent: self(), cwd: "/home/exedev", opts: []}
      result = Condukt.Sandbox.exec_tool(sandbox_pid, Condukt.Tools.Bash, %{"command" => "echo works"}, context)
      assert {:ok, output} = result
      assert output =~ "works"
    after
      Condukt.Sandbox.stop(sandbox_pid)
    end
  end
end
