defmodule Condukt.Workflows do
  @moduledoc """
  Public facade for Starlark-defined Condukt workflows.

  Workflows are loaded from a project root, materialized into Elixir structs,
  and can be invoked manually or supervised by a caller-owned runtime.
  """

  alias Condukt.Workflows.{Eval, Lockfile, Manifest, Project, Runtime, Store, Workflow}

  @doc """
  Loads a workflow project from `root`.
  """
  def load_project(root) when is_binary(root) do
    root = Path.expand(root)

    with {:ok, manifest, manifest_warnings} <- load_manifest(root),
         {:ok, lockfile} <- load_lockfile(root),
         {:ok, workflows} <- load_workflow_files(root, lockfile) do
      {:ok,
       %Project{
         root: root,
         manifest: manifest,
         lockfile: lockfile,
         workflows: workflows,
         warnings: manifest_warnings
       }}
    end
  end

  @doc """
  Returns all workflows materialized in a loaded project.
  """
  def list(%Project{workflows: workflows}) do
    workflows
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Fetches a workflow by name from a loaded project.
  """
  def get(%Project{workflows: workflows}, name) when is_binary(name) do
    case Map.fetch(workflows, name) do
      {:ok, workflow} -> {:ok, workflow}
      :error -> :error
    end
  end

  @doc """
  Runs one workflow once with the given input map.
  """
  def run(%Project{} = project, name, input) when is_binary(name) and is_map(input) do
    case get(project, name) do
      {:ok, workflow} -> Runtime.Worker.run_once(workflow, input)
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Starts a caller-owned workflow runtime supervisor.
  """
  def serve(%Project{} = project, opts \\ []) do
    Runtime.start_link(Keyword.put(opts, :project, project))
  end

  defp load_manifest(root) do
    path = Path.join(root, "condukt.toml")

    if File.exists?(path) do
      with {:ok, manifest} <- Manifest.load(path) do
        {:ok, manifest, manifest.warnings}
      end
    else
      {:ok, nil, []}
    end
  end

  defp load_lockfile(root) do
    case Lockfile.load(Path.join(root, "condukt.lock")) do
      {:ok, lockfile} -> {:ok, lockfile}
      :missing -> {:ok, %Lockfile{}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_workflow_files(root, lockfile) do
    store = Store.default()
    external_loader = &resolve_locked_load(&1, &2, lockfile, store)

    root
    |> Path.join("workflows/**/*.star")
    |> Path.wildcard(match_dot: false)
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}}, &load_and_merge_workflow_file(&1, &2, root, external_loader))
  end

  defp load_and_merge_workflow_file(path, {:ok, acc}, root, external_loader) do
    path
    |> load_workflow_file(root, external_loader)
    |> merge_loaded_workflows(acc)
  end

  defp merge_loaded_workflows({:ok, workflows}, acc) do
    case merge_workflows(acc, workflows) do
      {:ok, workflows} -> {:cont, {:ok, workflows}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp merge_loaded_workflows({:error, reason}, _acc), do: {:halt, {:error, reason}}

  defp load_workflow_file(path, root, external_loader) do
    with {:ok, %{"graph" => %{"workflows" => declarations}}} <-
           Eval.parse_file(path, external_loader: external_loader) do
      declarations
      |> Enum.map(&materialize_workflow(&1, path, root))
      |> Enum.reduce_while({:ok, []}, fn
        {:ok, workflow}, {:ok, acc} -> {:cont, {:ok, [workflow | acc]}}
        {:error, reason}, _acc -> {:halt, {:error, reason}}
      end)
      |> case do
        {:ok, workflows} -> {:ok, Enum.reverse(workflows)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp materialize_workflow(declaration, source_path, root) when is_map(declaration) do
    agent = Map.get(declaration, "agent") || %{}
    sandbox = normalize_project_sandbox(Map.get(agent, "sandbox"), root)

    workflow = %Workflow{
      name: Map.get(declaration, "name"),
      source_path: source_path,
      agent: agent,
      tools: Map.get(agent, "tools", []),
      sandbox: sandbox,
      triggers: Map.get(declaration, "triggers", []),
      inputs_schema: Map.get(declaration, "inputs_schema"),
      system_prompt: Map.get(declaration, "system_prompt") || Map.get(agent, "system_prompt"),
      model: Map.get(declaration, "model") || Map.get(agent, "model")
    }

    with :ok <- validate_workflow_name(workflow),
         {:ok, _opts} <- Workflow.to_session_opts(workflow) do
      {:ok, workflow}
    else
      {:error, reason} -> {:error, {:invalid_workflow, source_path, workflow.name, reason}}
    end
  end

  defp validate_workflow_name(%Workflow{name: name}) when is_binary(name) and name != "", do: :ok
  defp validate_workflow_name(_workflow), do: {:error, :missing_name}

  defp merge_workflows(acc, workflows) do
    Enum.reduce_while(workflows, {:ok, acc}, fn workflow, {:ok, acc} ->
      if Map.has_key?(acc, workflow.name) do
        {:halt, {:error, {:duplicate_workflow, workflow.name}}}
      else
        {:cont, {:ok, Map.put(acc, workflow.name, workflow)}}
      end
    end)
  end

  defp normalize_project_sandbox(nil, root), do: %{"kind" => "local", "cwd" => root}

  defp normalize_project_sandbox(%{"kind" => "local"} = sandbox, root) do
    cwd = Map.get(sandbox, "cwd") || root

    cwd =
      if Path.type(cwd) == :absolute do
        cwd
      else
        Path.expand(cwd, root)
      end

    Map.put(sandbox, "cwd", cwd)
  end

  defp normalize_project_sandbox(sandbox, _root), do: sandbox

  defp resolve_locked_load(load, _from_path, %Lockfile{packages: packages}, %Store{root: store_root}) do
    with {:ok, url_path, version} <- parse_external_load(load),
         {:ok, package_url, package, relative_path} <- find_locked_package(packages, url_path),
         :ok <- locked_version_matches(package_url, package, version),
         {:ok, source_path} <- locked_source_path(store_root, package, relative_path),
         {:ok, source} <- File.read(source_path) do
      {:ok, source_path, source}
    else
      {:error, reason} -> {:error, reason}
      {:error, reason, _path} -> {:error, reason}
    end
  end

  defp parse_external_load(load) do
    case String.split(load, "@", parts: 2) do
      [url_path, version] when url_path != "" and version != "" ->
        version = String.trim_leading(version, "v")

        case Version.parse(version) do
          {:ok, _version} -> {:ok, url_path, version}
          :error -> {:error, {:invalid_version, load}}
        end

      _ ->
        {:error, {:missing_version, load}}
    end
  end

  defp find_locked_package(packages, url_path) do
    packages
    |> Enum.filter(fn {url, _package} ->
      url_path == url or String.starts_with?(url_path, url <> "/")
    end)
    |> Enum.sort_by(fn {url, _package} -> byte_size(url) end, :desc)
    |> case do
      [{url, package} | _] ->
        relative_path =
          url_path
          |> String.replace_prefix(url, "")
          |> String.trim_leading("/")

        if relative_path == "" do
          {:error, {:missing_load_path, url_path}}
        else
          {:ok, url, package, relative_path}
        end

      [] ->
        {:error, {:missing_lock_package, url_path}}
    end
  end

  defp locked_version_matches(_package_url, %{version: version}, version), do: :ok

  defp locked_version_matches(package_url, package, requested),
    do: {:error, {:lock_version_mismatch, package_url, package.version, requested}}

  defp locked_source_path(store_root, %{sha256: sha256}, relative_path) when is_binary(sha256) and sha256 != "" do
    {:ok, Path.join([store_root, sha256, relative_path])}
  end

  defp locked_source_path(_store_root, _package, _relative_path), do: {:error, :missing_lock_sha256}
end
