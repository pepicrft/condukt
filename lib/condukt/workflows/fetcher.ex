defmodule Condukt.Workflows.Fetcher do
  @moduledoc """
  Behaviour for workflow package fetchers.
  """

  alias Condukt.Workflows.Manifest

  @type fetch_result :: %{
          optional(:tarball) => nil | binary(),
          required(:sha256) => String.t(),
          required(:version) => String.t(),
          required(:manifest) => Manifest.t()
        }

  @callback fetch(url :: String.t(), version :: String.t()) :: {:ok, fetch_result()} | {:error, term()}
  @callback list_versions(url :: String.t()) :: {:ok, [Version.t()]} | {:error, term()}
end
