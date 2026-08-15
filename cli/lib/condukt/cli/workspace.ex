defmodule Condukt.CLI.Workspace do
  @moduledoc """
  Direct workspace access for the commands that answer without a model.

  `/files`, `/read`, and their command-line equivalents inspect the workspace
  outside a session, so they read the filesystem here instead of going through
  the agent's tools, which need a running session and a sandbox.
  """

  @max_bytes 50_000

  @doc """
  Lists the files at the root of a workspace, sorted.

  Directories are left out: this answers "what is in this project" at a glance,
  not "walk the tree".
  """
  def files(root) do
    case File.ls(root) do
      {:ok, entries} ->
        {:ok,
         entries
         |> Enum.map(&Path.join(root, &1))
         |> Enum.filter(&File.regular?/1)
         |> Enum.sort()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reads a workspace file as text.

  Relative paths resolve against `root`. Output is truncated so a large file
  cannot flood the transcript.
  """
  def read(root, path) do
    resolved = resolve(root, path)

    case File.read(resolved) do
      {:ok, contents} -> {:ok, truncate(contents)}
      {:error, reason} -> {:error, "could not read #{resolved}: #{:file.format_error(reason)}"}
    end
  end

  @doc "Resolves a possibly relative path against the workspace root."
  def resolve(root, path) do
    if Path.type(path) == :absolute, do: path, else: Path.join(root, path)
  end

  @doc "Truncates output at a byte budget, on a character boundary."
  def truncate(output, max_bytes \\ @max_bytes) do
    if byte_size(output) <= max_bytes do
      output
    else
      output |> binary_part(0, character_boundary(output, max_bytes)) |> Kernel.<>("\n... (truncated)")
    end
  end

  defp character_boundary(output, boundary) do
    prefix = binary_part(output, 0, boundary)

    if String.valid?(prefix), do: boundary, else: character_boundary(output, boundary - 1)
  end
end
