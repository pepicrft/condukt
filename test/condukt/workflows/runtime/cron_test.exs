defmodule Condukt.Workflows.Runtime.CronTest do
  use ExUnit.Case, async: true

  alias Condukt.Workflows.{Runtime.Cron, Workflow}

  test "fires workflow invocations with injected clock and runner" do
    test_pid = self()

    pid =
      start_supervised!(
        {Cron,
         workflow: %Workflow{name: "triage"},
         expr: "* * * * * *",
         clock: fn -> ~N[2026-01-01 00:00:00] end,
         run_fun: fn name, input -> send(test_pid, {:cron_run, name, input}) end}
      )

    send(pid, :fire)

    assert_receive {:cron_run, "triage", %{}}
  end
end
