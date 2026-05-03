defmodule Condukt.Workflows.Lockfile do
  @moduledoc """
  Workflow dependency lockfile loaded from `condukt.lock`.
  """

  @type package :: %{
          version: String.t(),
          sha256: String.t(),
          integrity: String.t(),
          dependencies: [String.t()]
        }

  @type t :: %__MODULE__{
          version: pos_integer(),
          packages: %{String.t() => package()}
        }

  defstruct version: 1, packages: %{}

  @doc false
  def load(_path), do: not_implemented!()

  @doc false
  def write(_lockfile, _path), do: not_implemented!()

  @doc false
  def satisfies?(_lockfile, _requirements), do: not_implemented!()

  defp not_implemented!, do: raise(RuntimeError, "Condukt.Workflows.Lockfile is not implemented yet")
end
