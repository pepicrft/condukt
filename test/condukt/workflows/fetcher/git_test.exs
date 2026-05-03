defmodule Condukt.Workflows.Fetcher.GitTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Condukt.Workflows.Fetcher.Git

  setup :set_mimic_from_context
  setup :verify_on_exit!

  test "lists semantic versions from git tags" do
    MuonTrap
    |> expect(:cmd, fn "git", ["ls-remote", "--tags", "https://github.com/tuist/condukt-tools.git"], opts ->
      assert opts[:stderr_to_stdout] == true

      {"""
       abc\trefs/tags/v1.2.0
       def\trefs/tags/not-semver
       ghi\trefs/tags/1.3.0
       ghi\trefs/tags/1.3.0^{}
       """, 0}
    end)

    assert {:ok, versions} = Git.list_versions("github.com/tuist/condukt-tools")
    assert Enum.map(versions, &Version.to_string/1) == ["1.3.0", "1.2.0"]
  end

  @tag :tmp_dir
  @tag :workflows_nif
  test "fetches a git package and hashes the checkout" do
    MuonTrap
    |> expect(:cmd, fn "git",
                       [
                         "clone",
                         "--depth",
                         "1",
                         "--branch",
                         "1.2.0",
                         "https://github.com/tuist/condukt-tools.git",
                         target_dir
                       ],
                       opts ->
      assert opts[:stderr_to_stdout] == true
      File.mkdir_p!(Path.join(target_dir, "lib"))
      File.write!(Path.join(target_dir, "condukt.toml"), ~s(name = "demo"\nversion = "1.2.0"\n))
      File.write!(Path.join(target_dir, "lib/export.star"), "value = 1\n")
      {"cloned\n", 0}
    end)

    assert {:ok, fetched} = Git.fetch("github.com/tuist/condukt-tools", "1.2.0")
    assert fetched.version == "1.2.0"
    assert fetched.manifest.name == "demo"
    assert is_binary(fetched.sha256)

    File.rm_rf(fetched.source_dir)
  end
end
