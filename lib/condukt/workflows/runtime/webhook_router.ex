defmodule Condukt.Workflows.Runtime.WebhookRouter do
  @moduledoc """
  Plug-compatible router for workflow webhook triggers.
  """

  alias Condukt.Workflows.{Project, Runtime}

  @doc false
  def init(opts) do
    Keyword.put_new_lazy(opts, :routes, fn ->
      opts
      |> Keyword.fetch!(:project)
      |> routes()
    end)
  end

  @doc false
  def call(conn, opts) do
    ensure_plug!()

    path = request_path(conn)
    routes = Keyword.fetch!(opts, :routes)

    case {conn.method, Map.fetch(routes, path)} do
      {"POST", {:ok, workflow}} ->
        invoke(conn, workflow, opts)

      _ ->
        json(conn, 404, %{ok: false, error: "not_found"})
    end
  end

  defp invoke(conn, workflow, opts) do
    runner = Keyword.get(opts, :runner, fn workflow, input -> Runtime.Worker.invoke(workflow.name, input) end)

    with {:ok, input, conn} <- read_json_body(conn),
         {:ok, result} <- runner.(workflow, input) do
      json(conn, 200, %{ok: true, result: result})
    else
      {:error, :invalid_json, conn} -> json(conn, 400, %{ok: false, error: "invalid_json"})
      {:error, reason} -> json(conn, 500, %{ok: false, error: inspect(reason)})
    end
  end

  defp routes(%Project{workflows: workflows}) do
    workflows
    |> Map.values()
    |> Enum.flat_map(fn workflow ->
      workflow.triggers
      |> Enum.filter(&match?(%{"kind" => "webhook"}, &1))
      |> Enum.map(fn %{"path" => path} -> {normalize_path(path), workflow} end)
    end)
    |> Map.new()
  end

  defp read_json_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, "", conn} ->
        {:ok, %{}, conn}

      {:ok, body, conn} ->
        case JSON.decode(body) do
          {:ok, input} when is_map(input) -> {:ok, input, conn}
          _ -> {:error, :invalid_json, conn}
        end

      {:more, _partial, conn} ->
        {:error, :invalid_json, conn}

      {:error, _reason} ->
        {:error, :invalid_json, conn}
    end
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status, JSON.encode!(body))
  end

  defp request_path(conn) do
    conn.path_info
    |> Enum.join("/")
    |> then(&("/" <> &1))
    |> normalize_path()
  end

  defp normalize_path("/" <> _ = path), do: path
  defp normalize_path(path), do: "/" <> path

  defp ensure_plug! do
    if !Code.ensure_loaded?(Plug.Conn) do
      raise "Plug is required to use workflow webhook triggers"
    end
  end
end
