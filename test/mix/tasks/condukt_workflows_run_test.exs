defmodule Mix.Tasks.ConduktWorkflowsRunTest do
  use ExUnit.Case, async: false
  use Mimic

  import ExUnit.CaptureIO

  alias Condukt.Test.LLMProvider

  @moduletag :workflows_nif

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "runs a named workflow with JSON input" do
    root = Path.expand("../../fixtures/workflows_project", __DIR__)

    ReqLLM
    |> expect(:generate_text, fn "openai:gpt-4.1-mini", _context, _opts ->
      {:ok, LLMProvider.text_response("triaged")}
    end)

    output =
      capture_io(fn ->
        Mix.Task.rerun("condukt.workflows.run", [
          "triage",
          "--root",
          root,
          "--input",
          ~s({"issue":"broken"})
        ])
      end)

    assert output =~ "triaged"
  end
end
