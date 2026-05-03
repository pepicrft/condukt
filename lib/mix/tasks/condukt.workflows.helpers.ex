defmodule Mix.Tasks.Condukt.Workflows.Helpers do
  @moduledoc false

  alias Condukt.Workflows

  def parse!(args, switches) do
    case OptionParser.parse(args, strict: switches) do
      {opts, rest, []} -> {opts, rest}
      {_opts, _rest, invalid} -> Mix.raise("Invalid options: #{inspect(invalid)}")
    end
  end

  def root(opts) do
    opts
    |> Keyword.get(:root, File.cwd!())
    |> Path.expand()
  end

  def load_project!(root) do
    case Workflows.load_project(root) do
      {:ok, project} -> project
      {:error, reason} -> Mix.raise("Could not load workflow project: #{inspect(reason)}")
    end
  end

  def decode_input!(nil), do: %{}

  def decode_input!(encoded) do
    case JSON.decode(encoded) do
      {:ok, input} when is_map(input) -> input
      {:ok, _other} -> Mix.raise("--input must decode to a JSON object")
      {:error, reason} -> Mix.raise("Invalid --input JSON: #{inspect(reason)}")
    end
  end

  def format_result(result) when is_binary(result), do: result
  def format_result(result), do: JSON.encode!(result)
end
