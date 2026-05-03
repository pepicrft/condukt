defmodule Condukt.Workflows.RuntimeTest do
  use ExUnit.Case, async: false

  alias Condukt.Test.LLMProvider
  alias Condukt.Workflows.{Project, Runtime, Workflow}

  setup do
    handler_id = "workflow-runtime-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      [
        [:condukt, :workflow, :run, :start],
        [:condukt, :workflow, :run, :stop]
      ],
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  test "supervises workers and invokes a fresh session per run" do
    {model, model_id} = LLMProvider.model(LLMProvider.text_response("triaged"))
    workflow = workflow(model)
    project = %Project{root: File.cwd!(), workflows: %{workflow.name => workflow}}

    pid = start_supervised!({Runtime, project: project})

    assert {:ok, "triaged"} = Runtime.Worker.invoke("triage", %{"issue" => "broken"})
    assert_receive {LLMProvider, :request, ^model_id, _context, _opts}

    assert_receive {:telemetry, [:condukt, :workflow, :run, :start], %{system_time: _}, %{workflow: "triage"}}

    assert_receive {:telemetry, [:condukt, :workflow, :run, :stop], %{duration: _}, %{workflow: "triage"}}

    assert Process.alive?(pid)
  end

  test "public run helper invokes a workflow without starting the runtime" do
    {model, _model_id} = LLMProvider.model(LLMProvider.text_response("manual"))
    workflow = workflow(model)
    project = %Project{root: File.cwd!(), workflows: %{workflow.name => workflow}}

    assert {:ok, "manual"} = Condukt.Workflows.run(project, "triage", %{})
  end

  defp workflow(model) do
    %Workflow{
      name: "triage",
      source_path: Path.join(File.cwd!(), "workflows/triage.star"),
      model: model,
      system_prompt: "Triage incoming issues.",
      tools: [],
      sandbox: %{"kind" => "local", "cwd" => "."},
      inputs_schema: %{"type" => "object"},
      triggers: []
    }
  end
end
