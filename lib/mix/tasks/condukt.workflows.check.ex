defmodule Mix.Tasks.Condukt.Workflows.Check do
  @shortdoc "Validates Condukt workflows"

  @moduledoc """
  Validates a Condukt workflows project.
  """

  use Mix.Task

  alias Condukt.Workflows
  alias Mix.Tasks.Condukt.Workflows.Helpers

  @requirements ["app.start"]
  @impl Mix.Task
  def run(args) do
    {opts, rest} = Helpers.parse!(args, root: :string)
    rest == [] || Mix.raise("Unexpected arguments: #{Enum.join(rest, " ")}")

    root = Helpers.root(opts)
    project = Helpers.load_project!(root)

    case validate_project(project) do
      [] ->
        Mix.shell().info("Validated #{map_size(project.workflows)} workflow(s)")

      errors ->
        Enum.each(errors, fn error -> Mix.shell().error(format_error(error)) end)
        Mix.raise("Workflow validation failed")
    end
  end

  defp validate_project(project) do
    project
    |> Workflows.list()
    |> Enum.flat_map(fn workflow ->
      validate_model(workflow) ++ validate_session_opts(workflow)
    end)
  end

  defp validate_model(%{model: nil}), do: []

  defp validate_model(%{model: model} = workflow) when is_binary(model) do
    case parse_model(model) do
      :ok -> []
      {:error, reason} -> [{workflow, :invalid_model, "#{model}: #{inspect(reason)}"}]
    end
  end

  defp validate_model(%{model: model} = workflow), do: [{workflow, :invalid_model, inspect(model)}]

  defp validate_session_opts(workflow) do
    case Condukt.Workflows.Workflow.to_session_opts(workflow) do
      {:ok, _opts} -> []
      {:error, reason} -> [{workflow, :invalid_workflow, inspect(reason)}]
    end
  end

  defp parse_model(model) do
    cond do
      Code.ensure_loaded?(ReqLLM.Model) and function_exported?(ReqLLM.Model, :parse, 1) ->
        apply(ReqLLM.Model, :parse, [model]) |> normalize_parse_result()

      Code.ensure_loaded?(LLMDB) and function_exported?(LLMDB, :parse, 1) ->
        LLMDB.parse(model) |> normalize_parse_result()

      true ->
        ReqLLM.model(model) |> normalize_parse_result()
    end
  end

  defp normalize_parse_result({:ok, _value}), do: :ok
  defp normalize_parse_result({:error, reason}), do: {:error, reason}
  defp normalize_parse_result(other), do: {:error, other}

  defp format_error({workflow, kind, message}) do
    "#{workflow.source_path}:1:1: #{kind}: #{message}"
  end
end
