defmodule Condukt.Workflows.Fetcher.Git do
  @moduledoc """
  Git-backed workflow package fetcher.
  """

  @behaviour Condukt.Workflows.Fetcher

  alias Condukt.Workflows.{Manifest, NIF}

  @impl true
  def fetch(url, version) when is_binary(url) and is_binary(version) do
    target_dir = Path.join(System.tmp_dir!(), "condukt-workflows-#{System.unique_integer([:positive])}")
    repo_url = repo_url(url)

    case MuonTrap.cmd("git", ["clone", "--depth", "1", "--branch", version, repo_url, target_dir],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        load_fetch_result(target_dir, version)

      {output, exit_code} ->
        File.rm_rf(target_dir)
        {:error, {:git_clone_failed, exit_code, output}}
    end
  end

  @impl true
  def list_versions(url) when is_binary(url) do
    repo_url = repo_url(url)

    case MuonTrap.cmd("git", ["ls-remote", "--tags", repo_url], stderr_to_stdout: true) do
      {output, 0} -> {:ok, parse_versions(output)}
      {output, exit_code} -> {:error, {:git_ls_remote_failed, exit_code, output}}
    end
  end

  defp load_fetch_result(target_dir, version) do
    with {:ok, manifest} <- Manifest.load(Path.join(target_dir, "condukt.toml")),
         {:ok, sha256} <- NIF.sha256_tree(target_dir) do
      {:ok, %{tarball: nil, sha256: sha256, version: version, manifest: manifest, source_dir: target_dir}}
    else
      {:error, reason} ->
        File.rm_rf(target_dir)
        {:error, reason}
    end
  end

  defp repo_url("https://" <> _ = url), do: ensure_git_suffix(url)
  defp repo_url("http://" <> _ = url), do: ensure_git_suffix(url)
  defp repo_url(url), do: "https://#{url}" |> ensure_git_suffix()

  defp ensure_git_suffix(url) do
    if String.ends_with?(url, ".git"), do: url, else: url <> ".git"
  end

  defp parse_versions(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_tag_line/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort({:desc, Version})
  end

  defp parse_tag_line(line) do
    with [_sha, ref] <- String.split(line, "\t", parts: 2),
         "refs/tags/" <> tag <- String.trim(ref),
         tag = String.trim_trailing(tag, "^{}"),
         {:ok, version} <- tag |> String.trim_leading("v") |> Version.parse() do
      version
    else
      _ -> nil
    end
  end
end
