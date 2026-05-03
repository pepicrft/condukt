# Workflows

Workflows are Starlark files that declare reusable Condukt agents, inputs,
tools, sandboxes, and triggers. They are useful when a task should be loaded
from a project, checked before it runs, shared through git, locked for offline
use, or served by a small runtime.

Use `Condukt.Session` directly when the agent is defined in Elixir and lives in
your application code. Use workflows when the declaration should be data in a
project, portable across projects, and runnable through `mix
condukt.workflows.*` tasks.

## Anatomy of a workflow file

Workflow files live under `workflows/` and use the `.star` extension.

```python
condukt.workflow(
    name = "triage",
    agent = condukt.agent(
        model = "openai:gpt-4.1-mini",
        system_prompt = "Triage incoming issues.",
        tools = [condukt.tool("read"), condukt.tool("grep")],
        sandbox = condukt.sandbox.local(cwd = "."),
    ),
    triggers = [condukt.trigger.webhook(path = "/triage")],
    inputs = {"type": "object"},
)
```

`Condukt.Workflows.load_project/1` evaluates these files, materializes them as
Elixir structs, validates tool and sandbox references, and returns a
`Condukt.Workflows.Project`.

## The condukt builtin

The Starlark runtime exposes one `condukt` object:

| Function | Purpose |
| --- | --- |
| `condukt.workflow(name, agent, triggers, inputs, system_prompt, model)` | Declares one named workflow. |
| `condukt.agent(model, system_prompt, tools, thinking_level, sandbox)` | Declares the agent runtime options. |
| `condukt.tool(ref, **opts)` | Adds a tool by registry reference, for example `read` or `bash`. |
| `condukt.sandbox.local(cwd)` | Runs tools against the host filesystem rooted at `cwd`. |
| `condukt.sandbox.virtual(mounts)` | Runs tools against the virtual sandbox. |
| `condukt.schedule.cron(expr)` | Adds a cron trigger. |
| `condukt.trigger.webhook(path)` | Adds a webhook trigger. |
| `condukt.secret(name)` | Declares a secret reference for future integrations. |

Built-in load targets are also available:

```python
load("@condukt/tools", "tool")
load("@condukt/sandbox", "local", "virtual")
```

## Project layout

A workflow project uses this layout:

```text
condukt.toml
condukt.lock
workflows/*.star
lib/*.star
```

`condukt.toml` is optional for local projects. It is required when a project is
shared as a workflow package.

```toml
name = "support-workflows"
version = "1.0.0"
exports = ["lib/triage.star"]
requires_native = ["starlark", "pubgrub"]

[signatures]
```

`condukt.lock` is committed. It records selected package versions and content
hashes so workflow loads can run without network access.

## Sharing workflows

Workflow packages are plain git repositories with a `condukt.toml` at the root
and one or more exported `.star` files. Tag the repository with semantic
versions.

Consumers load shared files with a versioned URL:

```python
load("github.com/you/support-workflows/lib/triage.star@v1.0.0", "triage_agent")
```

Non-relative loads must include `@<version>`. Relative loads such as
`./helpers.star` and `../lib/tools.star` are workspace-only.

## The store

Fetched workflow packages are copied into a content-addressed store:

```text
~/.condukt/store/<sha256>/
```

The store key is the deterministic SHA-256 tree hash returned by the workflows
NIF. If fetched contents do not match the expected hash, the store write is
rejected.

## Resolution and the lockfile

Workflow dependency resolution uses PubGrub through the workflows NIF. The
lockfile is TOML:

```toml
version = 1

[packages."github.com/tuist/condukt-tools"]
version = "1.2.0"
url = "https://github.com/tuist/condukt-tools"
sha256 = "abcdef..."
integrity = "sha256-base64..."
dependencies = ["github.com/foo/bar"]
```

Run:

```sh
mix condukt.workflows.lock
```

Use `--offline` to require the existing lockfile to satisfy every requirement.
Use `--upgrade` when you want resolution to consider newer matching versions.

## Running workflows

When Condukt is installed as a library, use the Mix tasks. When Condukt is
installed as the standalone engine with mise, use the matching `condukt`
commands.

Check a project:

```sh
mix condukt.workflows.check --root .
condukt workflows check --root .
```

Run one workflow manually:

```sh
mix condukt.workflows.run triage --input '{"issue":"broken"}'
condukt workflows run triage --input '{"issue":"broken"}'
```

Start the runtime:

```sh
mix condukt.workflows.serve --port 4000
condukt workflows serve --port 4000
```

The runtime is caller-owned. The Condukt application supervisor does not start
it automatically.

## Triggers

Manual runs use `Condukt.Workflows.run/3`, `mix condukt.workflows.run`, or
`condukt workflows run`.

Cron triggers use `condukt.schedule.cron(expr)` and are supervised by
`Condukt.Workflows.Runtime.Cron`.

Webhook triggers use `condukt.trigger.webhook(path)`. When a served project has
webhook triggers and Bandit is available, the runtime starts an HTTP listener
and routes `POST` requests to the matching workflow worker.

## Validation

`mix condukt.workflows.check` and `condukt workflows check` load the project,
validate tool references, validate sandbox declarations, and check model
identifiers. Errors are reported with source file context:

```text
workflows/triage.star:1:1: invalid_model: bad
```

## Future hooks

The current subsystem keeps these features out of scope:

* Sigstore verification
* Hosted package discovery
* Dependency mirrors
* Rich secret provider integrations

Those can be added without changing the core file layout, lockfile format, or
runtime ownership model.
