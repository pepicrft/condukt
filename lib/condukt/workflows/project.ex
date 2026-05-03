defmodule Condukt.Workflows.Project do
  @moduledoc """
  Materialized workflow project.

  A project contains optional package metadata, an optional lockfile, and the
  set of workflows discovered under the project root.
  """

  alias Condukt.Workflows.{Lockfile, Manifest, Workflow}

  @type t :: %__MODULE__{
          root: Path.t(),
          manifest: Manifest.t() | nil,
          lockfile: Lockfile.t() | nil,
          workflows: %{String.t() => Workflow.t()},
          warnings: [term()]
        }

  defstruct [:root, :manifest, :lockfile, workflows: %{}, warnings: []]
end
