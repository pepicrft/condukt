defmodule Condukt.Workflows.Eval do
  @moduledoc """
  Starlark parsing and evaluation bridge for workflow files.
  """

  alias Condukt.Workflows.NIF

  @builtin_loads %{
    "@condukt/tools" => """
    tool = condukt.tool
    """,
    "@condukt/sandbox" => """
    local = condukt.sandbox.local
    virtual = condukt.sandbox.virtual
    """
  }

  @doc false
  def parse_file(path, opts \\ []) when is_binary(path) do
    path = Path.expand(path)

    with {:ok, source} <- File.read(path),
         {:ok, loads} <- collect_loads(path, source, %{}, MapSet.new(), opts) do
      NIF.eval(source, path, %{"__loads__" => loads})
    end
  end

  defp collect_loads(path, source, acc, seen, opts) do
    if MapSet.member?(seen, path) do
      {:ok, acc}
    else
      seen = MapSet.put(seen, path)

      with {:ok, %{"loads" => loads}} <- NIF.parse_only(source, path) do
        Enum.reduce_while(loads, {:ok, acc}, fn load, {:ok, acc} ->
          case resolve_load(load, path, opts) do
            {:ok, :builtin, load_source} ->
              {:cont, {:ok, Map.put_new(acc, load, load_source)}}

            {:ok, resolved_path, load_source} ->
              acc = Map.put_new(acc, load, load_source)

              case collect_loads(resolved_path, load_source, acc, seen, opts) do
                {:ok, acc} -> {:cont, {:ok, acc}}
                {:error, reason} -> {:halt, {:error, reason}}
              end

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)
      end
    end
  end

  defp resolve_load(load, from_path, _opts) do
    cond do
      Map.has_key?(@builtin_loads, load) ->
        {:ok, :builtin, Map.fetch!(@builtin_loads, load)}

      String.starts_with?(load, ["./", "../"]) ->
        resolve_relative_load(load, from_path)

      true ->
        {:error, {:invalid_url, "external workflow load is not resolved yet: #{load}"}}
    end
  end

  defp resolve_relative_load(load, from_path) do
    path =
      from_path
      |> Path.dirname()
      |> Path.join(load)
      |> Path.expand()

    case File.read(path) do
      {:ok, source} -> {:ok, path, source}
      {:error, reason} -> {:error, {:missing_load, load, reason}}
    end
  end
end
