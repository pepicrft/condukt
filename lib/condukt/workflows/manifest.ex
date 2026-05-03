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
  def load(path) when is_binary(path) do
    with {:ok, document} <- Toml.decode_file(path, keys: :strings) do
      parse(document)
    end
  end

  @doc false
  def parse(document) when is_map(document) do
    with {:ok, name} <- validate_name(Map.get(document, "name")),
         {:ok, version} <- validate_version(Map.get(document, "version")),
         {:ok, exports} <- validate_exports(Map.get(document, "exports", [])),
         {:ok, requires_native, warnings} <- validate_requires_native(Map.get(document, "requires_native", [])),
         {:ok, signatures} <- validate_signatures(Map.get(document, "signatures", %{})) do
      {:ok,
       %__MODULE__{
         name: name,
         version: version,
         exports: exports,
         requires_native: requires_native,
         signatures: signatures,
         warnings: warnings
       }}
    end
  end

  def parse(_document), do: {:error, {:invalid_manifest, "manifest must be a TOML table"}}

  defp validate_name(name) when is_binary(name) do
    if Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, name) do
      {:ok, name}
    else
      {:error, {:invalid_manifest, "name must be lowercase and hyphenated"}}
    end
  end

  defp validate_name(_), do: {:error, {:invalid_manifest, "name is required"}}

  defp validate_version(version) when is_binary(version) do
    case Version.parse(version) do
      {:ok, version} -> {:ok, version}
      :error -> {:error, {:invalid_manifest, "version must be semantic"}}
    end
  end

  defp validate_version(_), do: {:error, {:invalid_manifest, "version is required"}}

  defp validate_exports(exports) when is_list(exports) do
    if Enum.all?(exports, &valid_export?/1) do
      {:ok, exports}
    else
      {:error, {:invalid_manifest, "exports must be .star paths"}}
    end
  end

  defp validate_exports(_), do: {:error, {:invalid_manifest, "exports must be a list"}}

  defp valid_export?(path) when is_binary(path) do
    Path.type(path) == :relative and Path.extname(path) == ".star"
  end

  defp valid_export?(_), do: false

  defp validate_requires_native(requires_native) when is_list(requires_native) do
    if Enum.all?(requires_native, &is_binary/1) do
      warnings =
        requires_native
        |> Enum.reject(&known_native?/1)
        |> Enum.map(&{:unknown_native_requirement, &1})

      {:ok, requires_native, warnings}
    else
      {:error, {:invalid_manifest, "requires_native must be a list of strings"}}
    end
  end

  defp validate_requires_native(_), do: {:error, {:invalid_manifest, "requires_native must be a list"}}

  defp known_native?(requirement), do: requirement in ~w(starlark pubgrub sha2 bashkit)

  defp validate_signatures(signatures) when is_map(signatures), do: {:ok, signatures}
  defp validate_signatures(_), do: {:error, {:invalid_manifest, "signatures must be a table"}}
end
