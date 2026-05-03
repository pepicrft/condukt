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
      do_collect_loads(path, source, acc, seen, opts)
    end
  end

  defp do_collect_loads(path, source, acc, seen, opts) do
    seen = MapSet.put(seen, path)

    with {:ok, %{"loads" => loads}} <- NIF.parse_only(source, path) do
      Enum.reduce_while(loads, {:ok, acc}, &collect_load(&1, &2, path, seen, opts))
    end
  end

  defp collect_load(load, {:ok, acc}, path, seen, opts) do
    load
    |> resolve_load(path, opts)
    |> collect_resolved_load(load, acc, seen, opts)
  end

  defp collect_resolved_load({:ok, :builtin, load_source}, load, acc, _seen, _opts) do
    {:cont, {:ok, Map.put_new(acc, load, load_source)}}
  end

  defp collect_resolved_load({:ok, resolved_path, load_source}, load, acc, seen, opts) do
    acc = Map.put_new(acc, load, load_source)
    continue_collecting_loads(collect_loads(resolved_path, load_source, acc, seen, opts))
  end

  defp collect_resolved_load({:error, reason}, _load, _acc, _seen, _opts) do
    {:halt, {:error, reason}}
  end

  defp continue_collecting_loads({:ok, acc}), do: {:cont, {:ok, acc}}
  defp continue_collecting_loads({:error, reason}), do: {:halt, {:error, reason}}

  defp resolve_load(load, from_path, opts) do
    cond do
      Map.has_key?(@builtin_loads, load) ->
        {:ok, :builtin, Map.fetch!(@builtin_loads, load)}

      String.starts_with?(load, ["./", "../"]) ->
        resolve_relative_load(load, from_path)

      true ->
        resolve_external_load(load, from_path, opts)
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

  defp resolve_external_load(load, from_path, opts) do
    case Keyword.get(opts, :external_loader) do
      loader when is_function(loader, 2) ->
        loader.(load, from_path)

      _ ->
        {:error, {:invalid_url, "external workflow load is not resolved yet: #{load}"}}
    end
  end
end
