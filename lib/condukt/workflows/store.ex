defmodule Condukt.Workflows.Store do
  @moduledoc """
  Content-addressed local store for resolved workflow packages.
  """

  @type t :: %__MODULE__{root: Path.t()}

  defstruct [:root]

  @doc false
  def new(root) when is_binary(root), do: %__MODULE__{root: Path.expand(root)}

  @doc false
  def default do
    "~/.condukt/store"
    |> Path.expand()
    |> new()
  end

  @doc false
  def has?(_store, _sha256), do: not_implemented!()

  @doc false
  def put(_store, _source_dir, _sha256), do: not_implemented!()

  defp not_implemented!, do: raise(RuntimeError, "Condukt.Workflows.Store is not implemented yet")
end
