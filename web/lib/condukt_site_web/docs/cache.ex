defmodule ConduktSiteWeb.Docs.Cache do
  @moduledoc """
  Caches rendered documentation by source path and modification time.

  Documentation changes are picked up without restarting the development
  server, while production requests avoid rendering the same Markdown on every
  request.
  """

  use GenServer

  alias ConduktSiteWeb.Docs.Markdown

  @table __MODULE__

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put(opts, :name, __MODULE__))

  @spec get(Path.t()) :: Markdown.t()
  def get(file) do
    modified_at = modified_at(file)

    case :ets.lookup(@table, file) do
      [{^file, ^modified_at, page}] -> page
      _ -> GenServer.call(__MODULE__, {:render, file, modified_at})
    end
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:render, file, modified_at}, _from, state) do
    page =
      case :ets.lookup(@table, file) do
        [{^file, ^modified_at, page}] ->
          page

        _ ->
          page = file |> File.read!() |> Markdown.render()
          :ets.insert(@table, {file, modified_at, page})
          page
      end

    {:reply, page, state}
  end

  defp modified_at(file) do
    case File.stat(file, time: :posix) do
      {:ok, %File.Stat{mtime: modified_at}} -> modified_at
      _ -> 0
    end
  end
end
