defmodule Mix.Tasks.Condukt.Check do
  @moduledoc """
  Validates a Condukt workflow file without executing it.

      mix condukt.check path/to/workflow.star

  Reports parse errors, missing `run/1` definitions, and other static
  problems. Exits with status 1 when validation fails.
  """

  use Mix.Task

  @shortdoc "Validates a Condukt workflow file"

  @impl Mix.Task
  def run(argv) do
    case OptionParser.parse(argv, strict: []) do
      {_opts, [path], _} ->
        validate(path)

      _ ->
        Mix.shell().error("Usage: mix condukt.check PATH")
        exit({:shutdown, 1})
    end
  end

  defp validate(path) do
    case Condukt.Workflows.check(path) do
      :ok ->
        Mix.shell().info("ok: #{path}")

      {:error, diagnostics} when is_list(diagnostics) ->
        Enum.each(diagnostics, fn diag -> Mix.shell().error(format_diagnostic(diag)) end)
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("check failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp format_diagnostic(%{"line" => line, "col" => col, "message" => message}) do
    "#{line}:#{col}: #{message}"
  end

  defp format_diagnostic(%{"message" => message}), do: message
  defp format_diagnostic(other), do: inspect(other)
end
