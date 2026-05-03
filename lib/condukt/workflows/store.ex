defmodule Condukt.Workflows.Store do
  @moduledoc """
  Content-addressed local store for resolved workflow packages.
  """

  alias Condukt.Workflows.NIF

  defstruct [:root]

  @doc false
  def new(root) when is_binary(root), do: %__MODULE__{root: Path.expand(root)}

  @doc false
  def default do
    "~/.condukt/store"
    |> Path.expand()
    |> new()
  end

  @doc false
  def has?(%__MODULE__{root: root}, sha256) when is_binary(sha256) do
    root
    |> Path.join(sha256)
    |> Path.join("condukt.toml")
    |> File.exists?()
  end

  @doc false
  def put(%__MODULE__{} = store, source_dir, sha256) when is_binary(source_dir) and is_binary(sha256) do
    target = Path.join(store.root, sha256)

    if has?(store, sha256) do
      {:ok, target}
    else
      do_put(store, source_dir, sha256, target)
    end
  end

  defp do_put(%__MODULE__{root: root} = store, source_dir, sha256, target) do
    tmp = Path.join(root, "#{sha256}.tmp-#{System.unique_integer([:positive])}")

    with :ok <- File.mkdir_p(root),
         :ok <- reset_tmp(tmp),
         {:ok, _copied} <- File.cp_r(source_dir, tmp),
         {:ok, ^sha256} <- NIF.sha256_tree(tmp),
         :ok <- move_into_place(store, tmp, target, sha256) do
      {:ok, target}
    else
      {:ok, _other_sha} ->
        cleanup_integrity_mismatch(tmp)

      {:error, reason, _file} ->
        File.rm_rf(tmp)
        {:error, reason}

      {:error, reason} ->
        File.rm_rf(tmp)
        {:error, reason}
    end
  end

  defp reset_tmp(tmp) do
    case File.rm_rf(tmp) do
      {:ok, _} -> :ok
      {:error, reason, _file} -> {:error, reason}
    end
  end

  defp move_into_place(store, tmp, target, sha256) do
    if has?(store, sha256) do
      File.rm_rf(tmp)
      :ok
    else
      File.rename(tmp, target)
    end
  end

  defp cleanup_integrity_mismatch(tmp) do
    File.rm_rf(tmp)
    {:error, :integrity_mismatch}
  end
end
