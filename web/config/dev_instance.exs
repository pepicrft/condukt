defmodule ConduktSite.Config.DevInstance do
  @moduledoc """
  Allocates one stable development suffix per Git worktree.

  The suffix is shared by the local web port and database name, which lets
  multiple Condukt worktrees run concurrently without manual configuration.
  """

  @min_suffix 100
  @max_suffix 999
  @suffix_count @max_suffix - @min_suffix + 1
  @project_root Path.expand("..", __DIR__)
  @root_instance_file Path.join(@project_root, ".condukt-site-dev-instance")
  @git_instance_name "condukt-site-dev-instance"
  @env_var "CONDUKT_SITE_DEV_INSTANCE"

  def suffix do
    instance_file = resolve_instance_file()
    suffix = instance_file |> resolve_suffix() |> validate_suffix!()
    persist_suffix!(suffix, instance_file)
    suffix
  end

  def port(base), do: base + suffix()

  def database_name(base_name, options \\ []) do
    partition = Keyword.get(options, :partition, "") || ""
    "#{base_name}#{partition}_#{suffix()}"
  end

  defp resolve_instance_file do
    git_path(@git_instance_name) || @root_instance_file
  end

  defp resolve_suffix(instance_file) do
    [
      System.get_env(@env_var),
      read_suffix(instance_file),
      compatible_root_suffix(instance_file),
      generate_suffix(instance_file)
    ]
    |> Enum.find(& &1)
  end

  defp compatible_root_suffix(instance_file) do
    if root_fallback_applicable?(instance_file), do: read_suffix(@root_instance_file)
  end

  defp root_fallback_applicable?(instance_file) do
    instance_file == @root_instance_file || instance_file == main_checkout_instance_file()
  end

  defp main_checkout_instance_file do
    case git_common_dir() do
      nil -> nil
      directory -> Path.join(directory, @git_instance_name)
    end
  end

  defp git_common_dir do
    ["-C", @project_root, "rev-parse", "--path-format=absolute", "--git-common-dir"]
    |> run_git()
    |> normalize_git_path()
  end

  defp git_path(path) do
    Enum.find_value(
      [
        ["-C", @project_root, "rev-parse", "--path-format=absolute", "--git-path", path],
        ["-C", @project_root, "rev-parse", "--git-path", path]
      ],
      &(run_git(&1) |> normalize_git_path())
    )
  rescue
    ErlangError -> nil
  end

  defp normalize_git_path(""), do: nil
  defp normalize_git_path(nil), do: nil
  defp normalize_git_path("/" <> _ = path), do: path
  defp normalize_git_path(path), do: Path.expand(path, @project_root)

  defp run_git(arguments) do
    case System.cmd("git", arguments, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> nil
    end
  rescue
    ArgumentError -> nil
    ErlangError -> nil
  end

  defp read_suffix(path) do
    case File.read(path) do
      {:ok, suffix} ->
        case String.trim(suffix) do
          "" -> nil
          value -> value
        end

      {:error, _reason} ->
        nil
    end
  end

  defp generate_suffix(instance_file) do
    used_suffixes = used_suffixes(instance_file)

    instance_file
    |> candidate_suffixes()
    |> Enum.find(&(not MapSet.member?(used_suffixes, &1)))
    |> case do
      nil -> raise "failed to allocate a free #{@env_var} suffix"
      suffix -> suffix
    end
  end

  defp candidate_suffixes(instance_file) do
    start = :erlang.phash2(instance_file, @suffix_count)

    Enum.map(0..(@suffix_count - 1), fn offset ->
      @min_suffix + rem(start + offset, @suffix_count)
    end)
  end

  defp used_suffixes(instance_file) do
    known_instance_files()
    |> Enum.reject(&(&1 == instance_file))
    |> Enum.map(&read_suffix/1)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new(&validate_suffix!/1)
  end

  defp known_instance_files do
    worktree_files =
      case git_common_dir() do
        nil -> []
        directory -> Path.wildcard(Path.join([directory, "worktrees", "*", @git_instance_name]))
      end

    [@root_instance_file, main_checkout_instance_file() | worktree_files]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp validate_suffix!(suffix) do
    case Integer.parse(to_string(suffix)) do
      {value, ""} when value in @min_suffix..@max_suffix ->
        value

      _ ->
        raise "invalid #{@env_var} suffix #{inspect(suffix)}; expected 100 through 999"
    end
  end

  defp persist_suffix!(suffix, instance_file) do
    suffix = Integer.to_string(suffix)

    with {:error, reason} <- persist_suffix(suffix, instance_file),
         {:error, fallback_reason} <- persist_to_root_fallback(suffix, instance_file) do
      raise "failed to persist development suffix: #{inspect(reason)}, #{inspect(fallback_reason)}"
    end
  end

  defp persist_to_root_fallback(_suffix, @root_instance_file),
    do: {:error, :fallback_unavailable}

  defp persist_to_root_fallback(suffix, _instance_file) do
    persist_suffix(suffix, @root_instance_file)
  end

  defp persist_suffix(suffix, path) do
    with :ok <- File.mkdir_p(Path.dirname(path)), do: File.write(path, suffix)
  end
end
