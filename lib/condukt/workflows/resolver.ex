defmodule Condukt.Workflows.Resolver do
  @moduledoc """
  PubGrub-backed dependency resolver for workflow packages.
  """

  defmodule Requirement do
    @moduledoc """
    Dependency requirement extracted from a Starlark `load()` string.
    """

    @type t :: %__MODULE__{
            url: String.t(),
            version_spec: String.t()
          }

    defstruct [:url, :version_spec]
  end

  @doc false
  def collect_requirements(_project), do: not_implemented!()

  @doc false
  def resolve(_requirements, _opts \\ []), do: not_implemented!()

  defp not_implemented!, do: raise(RuntimeError, "Condukt.Workflows.Resolver is not implemented yet")
end
