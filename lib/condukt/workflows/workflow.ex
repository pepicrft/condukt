defmodule Condukt.Workflows.Workflow do
  @moduledoc """
  Materialized workflow declaration.

  The struct stores only Elixir data, never pointers into the Starlark runtime.
  """

  alias Condukt.Workflows.ToolRegistry

  @thinking_levels %{
    "off" => :off,
    "minimal" => :minimal,
    "low" => :low,
    "medium" => :medium,
    "high" => :high
  }

  @type t :: %__MODULE__{
          name: String.t(),
          source_path: Path.t(),
          agent: map() | nil,
          tools: [term()],
          sandbox: term(),
          triggers: [map()],
          inputs_schema: map() | nil,
          system_prompt: String.t() | nil,
          model: String.t() | nil
        }

  defstruct [
    :name,
    :source_path,
    :agent,
    :sandbox,
    :inputs_schema,
    :system_prompt,
    :model,
    tools: [],
    triggers: []
  ]

  @doc false
  def to_session_opts(%__MODULE__{} = workflow) do
    with {:ok, tools} <- resolve_tools(workflow.tools),
         {:ok, sandbox} <- resolve_sandbox(workflow),
         {:ok, thinking_level} <- resolve_thinking_level(workflow) do
      opts =
        [
          model: workflow.model,
          system_prompt: workflow.system_prompt,
          tools: tools,
          sandbox: sandbox,
          cwd: workflow_cwd(workflow),
          load_project_instructions: false,
          thinking_level: thinking_level
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, opts}
    end
  end

  defp resolve_tools(tools) when is_list(tools) do
    tools
    |> Enum.map(&ToolRegistry.resolve_tool/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, tool}, {:ok, acc} -> {:cont, {:ok, [tool | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, tools} -> {:ok, Enum.reverse(tools)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_tools(_tools), do: {:error, :invalid_tools}

  defp resolve_sandbox(%__MODULE__{sandbox: nil} = workflow) do
    {:ok, {Condukt.Sandbox.Local, cwd: workflow_cwd(workflow)}}
  end

  defp resolve_sandbox(%__MODULE__{sandbox: %{"kind" => "local"} = sandbox} = workflow) do
    cwd = sandbox["cwd"] || workflow_cwd(workflow)
    {:ok, {Condukt.Sandbox.Local, cwd: Path.expand(cwd, workflow_cwd(workflow))}}
  end

  defp resolve_sandbox(%__MODULE__{sandbox: %{"kind" => "virtual"} = sandbox}) do
    {:ok, {Condukt.Sandbox.Virtual, mounts: normalize_mounts(Map.get(sandbox, "mounts", []))}}
  end

  defp resolve_sandbox(%__MODULE__{sandbox: sandbox}), do: {:error, {:unknown_sandbox, sandbox}}

  defp normalize_mounts(mounts) when is_list(mounts) do
    Enum.map(mounts, fn
      [host, vfs] -> {host, vfs}
      [host, vfs, mode] -> {host, vfs, normalize_mode(mode)}
      %{"host" => host, "vfs" => vfs, "mode" => mode} -> {host, vfs, normalize_mode(mode)}
      %{"host" => host, "vfs" => vfs} -> {host, vfs}
      other -> other
    end)
  end

  defp normalize_mounts(_mounts), do: []

  defp normalize_mode("readonly"), do: :readonly
  defp normalize_mode("readwrite"), do: :readwrite
  defp normalize_mode(mode), do: mode

  defp resolve_thinking_level(workflow) do
    case get_in(workflow.agent || %{}, ["thinking_level"]) do
      nil -> {:ok, nil}
      level when is_atom(level) and level in [:off, :minimal, :low, :medium, :high] -> {:ok, level}
      level when is_binary(level) -> Map.fetch(@thinking_levels, level) |> normalize_thinking_level(level)
      level -> {:error, {:invalid_thinking_level, level}}
    end
  end

  defp normalize_thinking_level({:ok, level}, _raw), do: {:ok, level}
  defp normalize_thinking_level(:error, raw), do: {:error, {:invalid_thinking_level, raw}}

  defp workflow_cwd(%__MODULE__{source_path: source_path}) when is_binary(source_path) do
    Path.dirname(source_path)
  end

  defp workflow_cwd(_workflow), do: File.cwd!()
end
