# condukt_bashkit

Rustler NIF that wraps the [bashkit](https://github.com/everruns/bashkit)
virtual sandbox crate so that Condukt can offer a virtual filesystem and a
Rust-implemented bash interpreter through `Condukt.Sandbox.Virtual`.

## Distribution

This crate is built once per release on GitHub Actions across the supported
target matrix and published as precompiled NIF artifacts. End users install
Condukt via Hex without needing a Rust toolchain.

If you are working on Condukt itself, the crate is built from source by
`mix compile`. Rust toolchain is pinned in the repo's `mise.toml`.

## Cargo features enabled

* `git` — virtual git operations on the in-memory filesystem.
* `realfs` — host-directory mounting via `Bash::builder().mount_real_*`.
