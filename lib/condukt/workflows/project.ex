defmodule Condukt.Workflows.Project do
  @moduledoc """
  Materialized workflow project.

  A project contains optional package metadata, an optional lockfile, and the
  set of workflows discovered under the project root.
  """

  defstruct [:root, :manifest, :lockfile, workflows: %{}, warnings: []]
end
