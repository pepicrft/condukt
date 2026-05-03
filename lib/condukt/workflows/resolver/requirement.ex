defmodule Condukt.Workflows.Resolver.Requirement do
  @moduledoc """
  Dependency requirement extracted from a Starlark `load()` string.
  """

  defstruct [:url, :version_spec]
end
