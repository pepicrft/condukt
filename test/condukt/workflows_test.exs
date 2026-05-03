defmodule Condukt.WorkflowsTest do
  use ExUnit.Case, async: true

  alias Condukt.Workflows
  alias Condukt.Workflows.{Lockfile, Manifest, Project, Resolver, Store, Workflow}

  test "public facade exposes the pinned entry points" do
    assert Code.ensure_loaded?(Workflows)
    assert function_exported?(Workflows, :load_project, 1)
    assert function_exported?(Workflows, :list, 1)
    assert function_exported?(Workflows, :get, 2)
    assert function_exported?(Workflows, :run, 3)
    assert function_exported?(Workflows, :serve, 1)
    assert function_exported?(Workflows, :serve, 2)
  end

  test "project struct has the documented fields" do
    assert %Project{} = project = struct(Project)

    assert Map.take(Map.from_struct(project), [:root, :manifest, :lockfile, :workflows, :warnings]) == %{
             root: nil,
             manifest: nil,
             lockfile: nil,
             workflows: %{},
             warnings: []
           }
  end

  test "workflow struct has the documented fields" do
    assert %Workflow{} = workflow = struct(Workflow)

    assert Map.take(Map.from_struct(workflow), [
             :name,
             :source_path,
             :agent,
             :tools,
             :sandbox,
             :triggers,
             :inputs_schema,
             :system_prompt,
             :model
           ]) == %{
             name: nil,
             source_path: nil,
             agent: nil,
             tools: [],
             sandbox: nil,
             triggers: [],
             inputs_schema: nil,
             system_prompt: nil,
             model: nil
           }
  end

  test "manifest and lockfile structs have the documented fields" do
    assert %Manifest{} = manifest = struct(Manifest)
    assert %Lockfile{} = lockfile = struct(Lockfile)

    assert Map.take(Map.from_struct(manifest), [:name, :version, :exports, :requires_native, :signatures]) == %{
             name: nil,
             version: nil,
             exports: [],
             requires_native: [],
             signatures: %{}
           }

    assert Map.take(Map.from_struct(lockfile), [:version, :packages]) == %{version: 1, packages: %{}}
  end

  test "store and resolver requirement structs have the documented fields" do
    assert %Store{root: "/tmp/store"} = Store.new("/tmp/store")
    assert %Resolver.Requirement{url: "github.com/tuist/tools", version_spec: "^1.0.0"}
  end
end
