defmodule Mix.Tasks.Condukt.Workflows.Lock do
  @shortdoc "Writes the Condukt workflows lockfile"

  @moduledoc """
  Resolves workflow dependencies and writes condukt.lock.
  """

  use Mix.Task

  alias Condukt.Workflows.{Lockfile, NIF, Resolver}
  alias Mix.Tasks.Condukt.Workflows.Helpers

  @requirements ["app.start"]
  @impl Mix.Task
  def run(args) do
    {opts, rest} = Helpers.parse!(args, root: :string, upgrade: :boolean, offline: :boolean)
    rest == [] || Mix.raise("Unexpected arguments: #{Enum.join(rest, " ")}")

    root = Helpers.root(opts)
    lockfile = load_lockfile!(root)
    requirements = collect_requirements!(root)

    lockfile =
      requirements
      |> resolve(opts, lockfile)
      |> normalize_lockfile()

    path = Path.join(root, "condukt.lock")

    case Lockfile.write(lockfile, path) do
      :ok -> Mix.shell().info("Wrote #{path}")
      {:error, reason} -> Mix.raise("Could not write condukt.lock: #{inspect(reason)}")
    end
  end

  defp resolve([], _opts, _lockfile), do: {:ok, %Lockfile{}}

  defp resolve(requirements, opts, lockfile) do
    Resolver.resolve(requirements,
      lockfile: lockfile,
      offline: Keyword.get(opts, :offline, false),
      upgrade: Keyword.get(opts, :upgrade, false)
    )
  end

  defp normalize_lockfile({:ok, %Lockfile{} = lockfile}), do: lockfile
  defp normalize_lockfile({:ok, packages}) when is_map(packages), do: %Lockfile{packages: packages}

  defp normalize_lockfile({:error, reason}),
    do: Mix.raise("Could not resolve workflow dependencies: #{inspect(reason)}")

  defp load_lockfile!(root) do
    case Lockfile.load(Path.join(root, "condukt.lock")) do
      {:ok, lockfile} -> lockfile
      :missing -> %Lockfile{}
      {:error, reason} -> Mix.raise("Could not load condukt.lock: #{inspect(reason)}")
    end
  end

  defp collect_requirements!(root) do
    root
    |> workflow_sources()
    |> Enum.flat_map(&loads_for!/1)
    |> Resolver.collect_requirements()
  end

  defp workflow_sources(root) do
    ["workflows/**/*.star", "lib/**/*.star"]
    |> Enum.flat_map(fn pattern -> Path.wildcard(Path.join(root, pattern), match_dot: false) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp loads_for!(path) do
    with {:ok, source} <- File.read(path),
         {:ok, %{"loads" => loads}} <- NIF.parse_only(source, path) do
      loads
    else
      {:error, reason} -> Mix.raise("Could not parse #{path}: #{inspect(reason)}")
    end
  end
end
