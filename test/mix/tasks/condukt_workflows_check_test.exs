defmodule Mix.Tasks.ConduktWorkflowsCheckTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :workflows_nif

  test "validates a workflows project" do
    root = Path.expand("../../fixtures/workflows_project", __DIR__)

    output =
      capture_io(fn ->
        Mix.Task.rerun("condukt.workflows.check", ["--root", root])
      end)

    assert output =~ "Validated 1 workflow(s)"
  end
end
