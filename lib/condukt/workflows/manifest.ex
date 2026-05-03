defmodule Condukt.Workflows.Manifest do
  @moduledoc """
  Workflow package manifest loaded from `condukt.toml`.
  """

  @type t :: %__MODULE__{
          name: String.t() | nil,
          version: Version.t() | nil,
          exports: [Path.t()],
          requires_native: [String.t()],
          signatures: map(),
          warnings: [term()]
        }

  defstruct [:name, :version, exports: [], requires_native: [], signatures: %{}, warnings: []]

  @doc false
  def load(_path), do: not_implemented!()

  defp not_implemented!, do: raise(RuntimeError, "Condukt.Workflows.Manifest is not implemented yet")
end
