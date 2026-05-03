defmodule Condukt.Workflows do
  @moduledoc """
  Public facade for Starlark-defined Condukt workflows.

  Workflows are loaded from a project root, materialized into Elixir structs,
  and can be invoked manually or supervised by a caller-owned runtime.
  """

  alias Condukt.Workflows.{Project, Runtime, Workflow}

  @doc """
  Loads a workflow project from `root`.
  """
  @spec load_project(Path.t()) :: {:ok, Project.t()} | {:error, term()}
  def load_project(_root), do: not_implemented!()

  @doc """
  Returns all workflows materialized in a loaded project.
  """
  @spec list(Project.t()) :: [Workflow.t()]
  def list(%Project{workflows: workflows}) do
    workflows
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Fetches a workflow by name from a loaded project.
  """
  @spec get(Project.t(), String.t()) :: {:ok, Workflow.t()} | :error
  def get(%Project{workflows: workflows}, name) when is_binary(name) do
    case Map.fetch(workflows, name) do
      {:ok, workflow} -> {:ok, workflow}
      :error -> :error
    end
  end

  @doc """
  Runs one workflow once with the given input map.
  """
  @spec run(Project.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def run(_project, _name, _input), do: not_implemented!()

  @doc """
  Starts a caller-owned workflow runtime supervisor.
  """
  @spec serve(Project.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def serve(%Project{} = project, opts \\ []) do
    Runtime.start_link(Keyword.put(opts, :project, project))
  end

  defp not_implemented!, do: raise(RuntimeError, "Condukt.Workflows is not implemented yet")
end
