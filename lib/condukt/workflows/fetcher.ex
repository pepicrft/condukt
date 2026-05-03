defmodule Condukt.Workflows.Fetcher do
  @moduledoc """
  Behaviour for workflow package fetchers.
  """

  @callback fetch(url :: String.t(), version :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback list_versions(url :: String.t()) :: {:ok, [Version.t()]} | {:error, term()}
end
