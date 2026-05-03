defmodule Condukt.Bashkit.NIF do
  @moduledoc false
  # Low-level NIF binding to the bashkit virtual sandbox crate. This module
  # is internal: callers should use `Condukt.Sandbox.Virtual` and the
  # `Condukt.Sandbox.*` facade.

  use RustlerPrecompiled,
    otp_app: :condukt,
    crate: "condukt_bashkit",
    base_url: "https://github.com/tuist/condukt/releases/download/v#{Mix.Project.config()[:version]}",
    force_build:
      Mix.Project.get() == Condukt.MixProject or
        System.get_env("CONDUKT_BASHKIT_BUILD") in ["1", "true"],
    version: Mix.Project.config()[:version],
    targets: ~w(
      aarch64-apple-darwin
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      x86_64-apple-darwin
      x86_64-pc-windows-msvc
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
    ),
    nif_versions: ~w(2.16 2.17)

  # `mounts` is a list of {host_path, vfs_path, mode} tuples where mode is
  # `:readonly` or `:readwrite`.
  def new_session(_mounts), do: err()

  def shutdown(_session), do: err()

  def exec(_session, _command, _timeout_ms), do: err()

  def read_file(_session, _path), do: err()

  def write_file(_session, _path, _content), do: err()

  def edit_file(_session, _path, _old_text, _new_text), do: err()

  def glob(_session, _pattern, _cwd), do: err()

  def grep(_session, _pattern, _path, _case_sensitive, _file_glob), do: err()

  def mount(_session, _host_path, _vfs_path, _mode), do: err()

  def unmount(_session, _vfs_path), do: err()

  defp err, do: :erlang.nif_error(:nif_not_loaded)
end
