# Sandbox

A sandbox is a runtime-swappable backend for the operations a tool needs to
reach the outside world: read or write files, run shell commands, glob files,
search file contents. Built-in tools like `Condukt.Tools.Read` and
`Condukt.Tools.Bash` declare one tool name and JSON schema to the LLM and
route every primitive call through the active sandbox. The same agent
definition can therefore run against the host filesystem in development and
against an isolated virtual filesystem in production by changing one option
at session start.

## Built-in sandboxes

* `Condukt.Sandbox.Local` is the default. It operates against the host
  filesystem and spawns real bash subprocesses via `MuonTrap`.
* `Condukt.Sandbox.Virtual` runs against an in-memory virtual filesystem and
  a Rust-implemented bash interpreter (bashkit), with no host process
  spawning by default. It is shipped via a precompiled NIF, so consumers
  do not need a Rust toolchain to use it.

Custom sandboxes implement the `Condukt.Sandbox` behaviour and plug in the
same way.

## Virtual sandbox

`Condukt.Sandbox.Virtual` is backed by [bashkit](https://github.com/everruns/bashkit),
a virtual bash interpreter with an in-memory filesystem written in Rust. It
is loaded into the BEAM via a Rustler NIF.

```elixir
# Empty in-memory filesystem.
{:ok, sb} = Condukt.Sandbox.new(Condukt.Sandbox.Virtual)
{:ok, %{output: "hi\n", exit_code: 0}} = Condukt.Sandbox.exec(sb, "echo hi")

# Mount the host project at /workspace, read-only:
{:ok, sb} =
  Condukt.Sandbox.new(Condukt.Sandbox.Virtual,
    mounts: [{File.cwd!(), "/workspace", :readonly}]
  )

{:ok, contents} = Condukt.Sandbox.read(sb, "/workspace/mix.exs")

# Or mount at runtime:
:ok = Condukt.Sandbox.mount(sb, "/path/on/host", "/extra")
```

Each `exec/3` call is stateless: `cd`, `export`, and shell variables do
not persist across calls. This matches `Sandbox.Local`'s contract and
lets the `Condukt.Tools.Bash` tool behave identically in both sandboxes.

The precompiled NIF is built and attached to GitHub releases for the
following targets:

```
aarch64-apple-darwin
aarch64-unknown-linux-gnu
aarch64-unknown-linux-musl
x86_64-apple-darwin
x86_64-pc-windows-msvc
x86_64-unknown-linux-gnu
x86_64-unknown-linux-musl
```

Set `CONDUKT_BASHKIT_BUILD=1` (and have a Rust toolchain installed) to
force a source build.

### Sandbox-specific tools

`Condukt.Sandbox.Virtual.Tools.Mount` lets the agent mount a host
directory into the virtual filesystem at runtime. It only makes sense
with the Virtual sandbox; against `Sandbox.Local` it returns a clear
"not supported" error.

```elixir
def tools do
  Condukt.Tools.coding_tools() ++ [Condukt.Sandbox.Virtual.Tools.Mount]
end
```

## Picking a sandbox

Sessions resolve the sandbox in this order:

1. The `:sandbox` option passed to `start_link/1`.
2. The agent module's `sandbox/0` callback, if defined.
3. Default: `{Condukt.Sandbox.Local, cwd: <:cwd option or File.cwd!()>}`.

```elixir
# Default: Local sandbox rooted at the host cwd.
{:ok, agent} = MyApp.CodingAgent.start_link(api_key: "...")

# Local sandbox rooted at a specific directory.
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    api_key: "...",
    sandbox: {Condukt.Sandbox.Local, cwd: "/path/to/project"}
  )

# Virtual sandbox (when condukt_bashkit_nif is installed).
{:ok, agent} =
  MyApp.CodingAgent.start_link(
    api_key: "...",
    sandbox: Condukt.Sandbox.Virtual
  )
```

Or declare a default on the agent module:

```elixir
defmodule MyApp.CodingAgent do
  use Condukt

  @impl true
  def sandbox do
    {Condukt.Sandbox.Local, cwd: "/path/to/project"}
  end
end
```

## Sandbox-aware tools

If you write a custom tool that touches the filesystem or spawns processes,
route through the `Condukt.Sandbox.*` facade rather than calling `File.*`,
`System.cmd/3`, or `MuonTrap.cmd/3` directly. Direct calls bypass the
sandbox and break the ability to swap one in.

The facade:

```elixir
Condukt.Sandbox.read(sandbox, path)
Condukt.Sandbox.write(sandbox, path, content)
Condukt.Sandbox.edit(sandbox, path, old_text, new_text)
Condukt.Sandbox.exec(sandbox, command, opts)
Condukt.Sandbox.glob(sandbox, pattern, opts)
Condukt.Sandbox.grep(sandbox, pattern, opts)
Condukt.Sandbox.mount(sandbox, host_path, vfs_path)
```

The sandbox is in `context.sandbox` when your tool's `call/2` is invoked.
See the [Tools guide](tools.md) for an example.

## Writing a custom sandbox

Implement the `Condukt.Sandbox` behaviour. `init/1` builds the per-session
state, `shutdown/1` releases it, and the rest are I/O primitives:

```elixir
defmodule MyApp.S3Sandbox do
  @behaviour Condukt.Sandbox

  @impl true
  def init(opts), do: {:ok, %{bucket: opts[:bucket]}}

  @impl true
  def shutdown(_state), do: :ok

  @impl true
  def read_file(state, path), do: ExAws.S3.get_object(state.bucket, path) |> ExAws.request()

  # write_file/3, edit_file/4, exec/3, plus optional glob/3, grep/3, mount/3
end
```

`glob/3`, `grep/3`, and `mount/3` are optional callbacks. The facade returns
`{:error, :not_supported}` when a sandbox does not implement them.

## Why sandboxes

Two reasons.

First, isolation: in multi-tenant deployments you may not want every agent
to read or write the host filesystem unrestricted. A virtual sandbox lets
you mount only the directories an agent should see and bound everything
else.

Second, portability: the same agent definition runs in development against
the real project (Local) and in production against an in-memory snapshot
(Virtual) without any code changes. Tests can build an isolated sandbox per
case and tear it down without touching disk.
