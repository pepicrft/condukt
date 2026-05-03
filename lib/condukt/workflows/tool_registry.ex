defmodule Condukt.Workflows.ToolRegistry do
  @moduledoc """
  Resolves Starlark workflow tool references to Condukt tool modules.
  """

  @known %{
    "read" => Condukt.Tools.Read,
    "bash" => Condukt.Tools.Bash,
    "edit" => Condukt.Tools.Edit,
    "write" => Condukt.Tools.Write,
    "glob" => Condukt.Tools.Glob,
    "grep" => Condukt.Tools.Grep,
    "command" => Condukt.Tools.Command,
    "sandbox.virtual.mount" => Condukt.Sandbox.Virtual.Tools.Mount
  }

  @doc false
  def resolve_tool(%{"ref" => ref, "opts" => opts}) when is_binary(ref) and is_map(opts) do
    with {:ok, module} <- resolve(ref) do
      opts = opts_to_keyword(opts)
      {:ok, if(opts == [], do: module, else: {module, opts})}
    end
  end

  def resolve_tool(%{"ref" => ref}) when is_binary(ref), do: resolve_tool(%{"ref" => ref, "opts" => %{}})
  def resolve_tool(ref) when is_binary(ref), do: resolve_tool(%{"ref" => ref, "opts" => %{}})
  def resolve_tool(tool) when is_atom(tool), do: {:ok, tool}
  def resolve_tool({module, opts}) when is_atom(module) and is_list(opts), do: {:ok, {module, opts}}
  def resolve_tool(tool), do: {:error, {:invalid_tool, tool}}

  @doc false
  def resolve(ref) when is_binary(ref) do
    case Map.fetch(@known, ref) do
      {:ok, module} -> {:ok, module}
      :error -> resolve_custom(ref)
    end
  end

  defp resolve_custom(ref) do
    module = custom_module(ref)

    if Code.ensure_loaded?(module) do
      {:ok, module}
    else
      {:error, {:unknown_tool, ref}}
    end
  end

  defp custom_module(ref) do
    suffix =
      ref
      |> String.split(".")
      |> Enum.map_join("", &Macro.camelize/1)

    Module.concat(Condukt.Workflows.Tools, suffix)
  end

  defp opts_to_keyword(opts) do
    opts
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> {option_key(key), value} end)
  end

  defp option_key(key) when is_atom(key), do: key
  defp option_key(key) when is_binary(key), do: String.to_atom(key)
end
