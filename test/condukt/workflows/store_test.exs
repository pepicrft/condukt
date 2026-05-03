defmodule Condukt.Workflows.StoreTest do
  use ExUnit.Case, async: false

  alias Condukt.Workflows.{NIF, Store}

  @moduletag :workflows_nif

  @tag :tmp_dir
  test "puts packages into the content-addressed store", %{tmp_dir: tmp_dir} do
    package_dir = package_fixture(tmp_dir)
    store = Store.new(Path.join(tmp_dir, "store"))

    assert {:ok, sha256} = NIF.sha256_tree(package_dir)
    refute Store.has?(store, sha256)

    assert {:ok, target} = Store.put(store, package_dir, sha256)
    assert Store.has?(store, sha256)
    assert File.read!(Path.join(target, "condukt.toml")) =~ "demo"

    assert {:ok, ^target} = Store.put(store, package_dir, sha256)
  end

  @tag :tmp_dir
  test "rejects integrity mismatches and removes the temp copy", %{tmp_dir: tmp_dir} do
    package_dir = package_fixture(tmp_dir)
    store = Store.new(Path.join(tmp_dir, "store"))

    assert {:error, :integrity_mismatch} = Store.put(store, package_dir, String.duplicate("0", 64))
    refute File.exists?(Path.join(store.root, String.duplicate("0", 64)))
    assert [] = Path.wildcard(Path.join(store.root, "*.tmp-*"))
  end

  defp package_fixture(tmp_dir) do
    package_dir = Path.join(tmp_dir, "package")
    File.mkdir_p!(Path.join(package_dir, "lib"))
    File.write!(Path.join(package_dir, "condukt.toml"), ~s(name = "demo"\nversion = "0.1.0"\n))
    File.write!(Path.join(package_dir, "lib/tool.star"), "helper = 1\n")
    package_dir
  end
end
