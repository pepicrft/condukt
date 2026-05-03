defmodule Condukt.Workflows.Runtime do
  @moduledoc """
  Caller-owned supervisor for workflow workers and triggers.
  """

  use Supervisor

  alias Condukt.Workflows.{Project, Runtime}

  @doc false
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    project = Keyword.fetch!(opts, :project)

    children =
      [
        {Registry, keys: :unique, name: Condukt.Workflows.Registry}
      ] ++ worker_children(project) ++ cron_children(project) ++ webhook_children(project, opts)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp worker_children(%Project{workflows: workflows}) do
    workflows
    |> Map.values()
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn workflow ->
      %{
        id: {Runtime.Worker, workflow.name},
        start: {Runtime.Worker, :start_link, [[workflow: workflow]]},
        restart: :transient
      }
    end)
  end

  defp cron_children(%Project{workflows: workflows}) do
    workflows
    |> Map.values()
    |> Enum.sort_by(& &1.name)
    |> Enum.flat_map(fn workflow ->
      workflow.triggers
      |> Enum.filter(&match?(%{"kind" => "cron"}, &1))
      |> Enum.with_index()
      |> Enum.map(fn {%{"expr" => expr}, index} ->
        %{
          id: {Runtime.Cron, workflow.name, index},
          start: {Runtime.Cron, :start_link, [[workflow: workflow, expr: expr]]},
          restart: :permanent
        }
      end)
    end)
  end

  defp webhook_children(%Project{} = project, opts) do
    if webhook_triggers?(project) and Runtime.WebhookListener.available?() do
      [
        Runtime.WebhookListener.child_spec(
          project: project,
          port: Keyword.get(opts, :port, 4000),
          ip: Keyword.get(opts, :ip)
        )
      ]
    else
      []
    end
  end

  defp webhook_triggers?(%Project{workflows: workflows}) do
    workflows
    |> Map.values()
    |> Enum.any?(fn workflow ->
      Enum.any?(workflow.triggers, &match?(%{"kind" => "webhook"}, &1))
    end)
  end
end
