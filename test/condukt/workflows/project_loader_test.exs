defmodule Condukt.Workflows.ProjectLoaderTest do
  use ExUnit.Case, async: false

  alias Condukt.Workflows
  alias Condukt.Workflows.Lockfile

  @moduletag :workflows_nif

  test "loads and materializes workflows from a project root" do
    root = Path.expand("../../fixtures/workflows_project", __DIR__)

    assert {:ok, project} = Workflows.load_project(root)
    assert project.root == root
    assert %Lockfile{} = project.lockfile

    assert [workflow] = Workflows.list(project)
    assert workflow.name == "triage"
    assert workflow.model == "openai:gpt-4.1-mini"
    assert workflow.system_prompt == "Triage incoming issues."
    assert workflow.sandbox["cwd"] == root
    assert workflow.tools == [%{"opts" => %{}, "ref" => "read", "type" => "tool"}]
    assert workflow.triggers == [%{"kind" => "webhook", "path" => "/triage", "type" => "trigger"}]

    assert {:ok, ^workflow} = Workflows.get(project, "triage")
  end
end
