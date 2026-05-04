defmodule Condukt.Workflows do
  @moduledoc """
  Public facade for Starlark-defined Condukt workflows.

  A workflow is a single self-contained `.star` file that defines a
  top-level `run(inputs)` function and calls `workflow(inputs = ...)` to
  declare its inputs schema. The basename of the file is the run name.

  The runtime evaluates the file on a dedicated OS thread. When the
  workflow calls a suspending builtin like `run_cmd(...)`, the Starlark
  VM blocks while the host performs the side effect, then resumes with
  the real return value.
  """

  alias Condukt.Workflows.{Builtins, NIF}

  @type input :: map()
  @type result :: term()

  @doc """
  Runs a workflow `.star` file with the given inputs.

  `path` must be a path to a local file. Remote URL loading is planned
  for a later slice.
  """
  @spec run(Path.t(), input(), keyword()) :: {:ok, result()} | {:error, term()}
  def run(path, inputs \\ %{}, opts \\ []) when is_binary(path) and is_map(inputs) do
    case read_source(path) do
      {:ok, source} -> drive(source, path, JSON.encode!(inputs), opts)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates a workflow file without executing it.

  Returns `:ok` when the file parses and declares a workflow correctly.
  Returns `{:error, reason}` when the file fails parsing or static checks.
  """
  @spec check(Path.t()) :: :ok | {:error, term()}
  def check(path) when is_binary(path) do
    with {:ok, source} <- read_source(path),
         {:ok, %{"ok" => true}} <- NIF.check(source, path) do
      :ok
    else
      {:ok, %{"ok" => false, "diagnostics" => diagnostics}} -> {:error, diagnostics}
      {:error, reason} -> {:error, reason}
    end
  end

  defp drive(source, path, inputs_json, opts) do
    case NIF.start_run(source, path, inputs_json) do
      {:ok, {handle, event}} -> drive_loop(handle, event, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp drive_loop(_handle, {:done, json}, _opts) do
    decode_json(json)
  end

  defp drive_loop(_handle, {:error, message}, _opts) do
    {:error, message}
  end

  defp drive_loop(handle, {:suspended, json}, opts) do
    with {:ok, request} <- decode_json(json),
         response = Builtins.handle(request, opts),
         {:ok, event} <- NIF.resume_run(handle, JSON.encode!(response)) do
      drive_loop(handle, event, opts)
    else
      {:error, reason} ->
        _ = NIF.cancel_run(handle)
        {:error, reason}
    end
  end

  defp read_source(path) do
    case File.read(path) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:error, {:read_failed, path, reason}}
    end
  end

  defp decode_json(""), do: {:ok, nil}
  defp decode_json("null"), do: {:ok, nil}

  defp decode_json(json) when is_binary(json) do
    case JSON.decode(json) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:decode_failed, reason}}
    end
  end
end
