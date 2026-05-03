defmodule Condukt.Workflows.Fetcher.Git do
  @moduledoc """
  Git-backed workflow package fetcher.
  """

  @behaviour Condukt.Workflows.Fetcher

  @impl true
  def fetch(_url, _version), do: not_implemented!()

  @impl true
  def list_versions(_url), do: not_implemented!()

  defp not_implemented!, do: raise(RuntimeError, "Condukt.Workflows.Fetcher.Git is not implemented yet")
end
