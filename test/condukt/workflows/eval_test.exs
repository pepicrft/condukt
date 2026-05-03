defmodule Condukt.Workflows.EvalTest do
  use ExUnit.Case, async: false

  alias Condukt.Workflows.Eval

  @moduletag :workflows_nif

  test "round-trips a workflow fixture through the NIF" do
    path = Path.expand("../../fixtures/workflows/triage.star", __DIR__)

    assert {:ok, %{"graph" => %{"workflows" => [workflow]}, "loads" => []}} = Eval.parse_file(path)

    assert workflow["name"] == "triage"
    assert workflow["agent"]["model"] == "openai:gpt-4.1-mini"
    assert workflow["agent"]["tools"] == [%{"opts" => %{}, "ref" => "read", "type" => "tool"}]
    assert workflow["triggers"] == [%{"kind" => "webhook", "path" => "/triage", "type" => "trigger"}]
  end
end
