defmodule Condukt.Workflows.Resolver do
  @moduledoc """
  PubGrub-backed dependency resolver for workflow packages.
  """

  alias Condukt.Workflows.Fetcher.Git
  alias Condukt.Workflows.{Lockfile, NIF, Project, Store}

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
  def collect_requirements(%Project{workflows: workflows}) do
    workflows
    |> Map.values()
    |> Enum.flat_map(&collect_workflow_requirements/1)
    |> Enum.uniq_by(&{&1.url, &1.version_spec})
    |> Enum.sort_by(&{&1.url, &1.version_spec})
  end

  def collect_requirements(loads) when is_list(loads) do
    loads
    |> Enum.flat_map(fn
      load when is_binary(load) ->
        case parse_requirement(load) do
          {:ok, requirement} -> [requirement]
          :relative -> []
          {:error, _reason} -> []
        end

      _ ->
        []
    end)
  end

  @doc false
  def resolve(requirements, opts \\ []) when is_list(requirements) do
    requirements = Enum.sort_by(requirements, &{&1.url, &1.version_spec})
    lockfile = opts[:lockfile] || opts[:lock]

    cond do
      opts[:offline] && match?(%Lockfile{}, lockfile) && Lockfile.satisfies?(lockfile, requirements) ->
        {:ok, lockfile}

      opts[:offline] ->
        {:error, :lockfile_not_satisfied}

      true ->
        do_resolve(requirements, opts)
    end
  end

  @doc false
  def parse_requirement("./" <> _), do: :relative
  def parse_requirement("../" <> _), do: :relative

  def parse_requirement(load) when is_binary(load) do
    case String.split(load, "@", parts: 2) do
      [url, version] when url != "" and version != "" ->
        if valid_requirement_url?(url) and valid_version?(version) do
          {:ok, %Requirement{url: url, version_spec: String.trim_leading(version, "v")}}
        else
          {:error, {:invalid_requirement, load}}
        end

      _ ->
        {:error, {:missing_version, load}}
    end
  end

  defp do_resolve(requirements, opts) do
    with {:ok, index} <- build_index(requirements, opts),
         {:ok, selected} <- NIF.resolve("__root__", Enum.map(requirements, &requirement_map/1), index_for_nif(index)) do
      {:ok, selected_to_lock_packages(selected, index)}
    end
  end

  defp collect_workflow_requirements(%{source_path: source_path}) when is_binary(source_path) do
    with {:ok, source} <- File.read(source_path),
         {:ok, %{"loads" => loads}} <- NIF.parse_only(source, source_path) do
      collect_requirements(loads)
    else
      _ -> []
    end
  end

  defp collect_workflow_requirements(_), do: []

  defp build_index(requirements, opts) do
    case Keyword.get(opts, :index) do
      index when is_map(index) ->
        {:ok, index}

      _ ->
        fetcher = Keyword.get(opts, :fetcher, Git)
        store = Keyword.get_lazy(opts, :store, &Store.default/0)

        requirements
        |> Enum.reduce_while({:ok, %{}}, fn requirement, {:ok, index} ->
          case index_requirement(requirement, fetcher, store) do
            {:ok, package_index} -> {:cont, {:ok, Map.put(index, requirement.url, package_index)}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp index_requirement(%Requirement{url: url}, fetcher, store) do
    with {:ok, versions} <- fetcher.list_versions(url) do
      versions
      |> Enum.reduce_while({:ok, %{}}, fn version, {:ok, acc} ->
        version_string = Version.to_string(version)

        case fetcher.fetch(url, version_string) do
          {:ok, fetched} ->
            maybe_store(fetcher, store, fetched)
            {:cont, {:ok, Map.put(acc, version_string, fetch_to_index_info(fetched))}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp maybe_store(_fetcher, store, %{source_dir: source_dir, sha256: sha256}) do
    _ = Store.put(store, source_dir, sha256)
    File.rm_rf(source_dir)
    :ok
  end

  defp maybe_store(_fetcher, _store, _fetched), do: :ok

  defp fetch_to_index_info(fetched) do
    %{
      sha256: fetched.sha256,
      integrity: integrity(fetched.sha256),
      dependencies: Map.get(fetched, :dependencies, [])
    }
  end

  defp index_for_nif(index) do
    Map.new(index, fn {url, versions} ->
      {url,
       Map.new(versions, fn {version, info} ->
         {version, %{dependencies: Enum.map(Map.get(info, :dependencies, []), &requirement_map/1)}}
       end)}
    end)
  end

  defp selected_to_lock_packages(selected, index) do
    selected
    |> Map.new(fn {url, version} ->
      info = get_in(index, [url, version]) || %{}

      {url,
       %{
         version: version,
         sha256: Map.get(info, :sha256, ""),
         integrity: Map.get(info, :integrity, integrity(Map.get(info, :sha256, ""))),
         dependencies: dependency_urls(Map.get(info, :dependencies, []))
       }}
    end)
  end

  defp dependency_urls(dependencies) do
    dependencies
    |> Enum.map(fn
      %Requirement{url: url} -> url
      %{url: url} -> url
    end)
    |> Enum.sort()
  end

  defp requirement_map(%Requirement{} = requirement) do
    %{url: requirement.url, version_spec: requirement.version_spec}
  end

  defp requirement_map(%{url: url, version_spec: version_spec}) do
    %{url: url, version_spec: version_spec}
  end

  defp valid_requirement_url?(url) do
    String.contains?(url, "/") and not String.starts_with?(url, ["./", "../", "http://", "https://"])
  end

  defp valid_version?(version) do
    version
    |> String.trim_leading("v")
    |> Version.parse()
    |> case do
      {:ok, _version} -> true
      :error -> false
    end
  end

  defp integrity(""), do: ""

  defp integrity(sha256) do
    case Base.decode16(sha256, case: :mixed) do
      {:ok, decoded} -> "sha256-" <> Base.encode64(decoded)
      :error -> ""
    end
  end
end
