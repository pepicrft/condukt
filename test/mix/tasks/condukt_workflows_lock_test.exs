defmodule Mix.Tasks.ConduktWorkflowsLockTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :workflows_nif
  @tag :tmp_dir
  test "writes an empty deterministic lockfile when there are no external loads", %{tmp_dir: root} do
    workflow_dir = Path.join(root, "workflows")
    File.mkdir_p!(workflow_dir)

    File.write!(Path.join(workflow_dir, "triage.star"), """
    condukt.workflow(
        name = "triage",
        agent = condukt.agent(model = "openai:gpt-4.1-mini"),
    )
    """)

    output =
      capture_io(fn ->
        Mix.Task.rerun("condukt.workflows.lock", ["--root", root])
      end)

    assert output =~ "Wrote #{Path.join(root, "condukt.lock")}"
    assert File.read!(Path.join(root, "condukt.lock")) =~ "version = 1"
  end
end
