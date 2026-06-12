# condukt_microsandbox

Rustler NIF that wraps the
[microsandbox](https://github.com/superradcompany/microsandbox) crate so
Condukt can run a session inside a microVM through
`Condukt.Sandbox.Microsandbox`.

## Distribution

This crate follows the same release model as `condukt_bashkit`: supported
targets are published as precompiled NIF artifacts on GitHub releases, while
`MIX_ENV=dev` and `MIX_ENV=test` build from source in the Condukt repo.
Set `CONDUKT_MICROSANDBOX_DISABLE=1` when a task only needs the Elixir modules
to compile and must not invoke the Rust toolchain.

Microsandbox itself is host-platform dependent. Condukt currently exposes this
backend on:

* `aarch64-apple-darwin`
* `aarch64-unknown-linux-gnu`
* `x86_64-unknown-linux-gnu`

Unsupported targets compile the Elixir wrapper as stubs that return
`{:error, :unsupported_target}`.
