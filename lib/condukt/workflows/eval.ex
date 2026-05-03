defmodule Condukt.Workflows.Eval do
  @moduledoc """
  Starlark parsing and evaluation bridge for workflow files.
  """

  @doc false
  def parse_file(_path, _opts \\ []), do: not_implemented!()

  defp not_implemented!, do: raise(RuntimeError, "Condukt.Workflows.Eval is not implemented yet")
end
