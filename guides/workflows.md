# Workflows

Workflows are Starlark files that declare reusable Condukt agents, inputs,
tools, sandboxes, and triggers. They let you keep agentic automation as project
data that can be checked, locked, shared through git, and run by the standalone
`condukt` engine or by Mix tasks in an Elixir project.

Use `Condukt.Session` directly when the agent belongs in application code and
is supervised by your own OTP tree. Use workflows when the declaration should
travel with a project, be runnable from a terminal, or be shared with other
teams.

## Create a workflow project

A workflow project can be as small as one `.star` file:

```text
my-workflows/
  condukt.lock
  workflows/
    triage.star
```

`condukt.lock` is committed. It can start empty:

```toml
version = 1
```

Create `workflows/triage.star`:

```python
condukt.workflow(
    name = "triage",
    agent = condukt.agent(
        model = "openai:gpt-4.1-mini",
        system_prompt = "Triage incoming issues.",
        tools = [condukt.tool("read"), condukt.tool("grep")],
        sandbox = condukt.sandbox.local(cwd = "."),
    ),
    inputs = {"type": "object"},
)
```

The workflow name is the command name you run later. The `inputs` value is a
JSON Schema map. It is validated before the workflow starts.

## Check and run locally

When Condukt is installed as a library, use the Mix tasks:

```sh
mix condukt.workflows.check --root .
mix condukt.workflows.run triage --root . --input '{"issue":"broken"}'
```

When Condukt is installed as the standalone engine, use the matching commands:

```sh
condukt workflows check --root .
condukt workflows run triage --root . --input '{"issue":"broken"}'
```

Both paths load the project, evaluate the Starlark files, validate tool
references, validate sandbox declarations, and check model identifiers. Errors
are reported with source file context:

```text
workflows/triage.star:1:1: invalid_model: bad
```

## Serve workflows

Workflows can be served by a caller-owned runtime. The Condukt application
supervisor does not start workflow runtimes automatically.

```sh
mix condukt.workflows.serve --root . --port 4000
condukt workflows serve --root . --port 4000
```

Manual runs use `Condukt.Workflows.run/3`, `mix condukt.workflows.run`, or
`condukt workflows run`.

Cron triggers use `condukt.schedule.cron(expr)`:

```python
condukt.workflow(
    name = "daily_summary",
    agent = condukt.agent(model = "openai:gpt-4.1-mini"),
    triggers = [condukt.schedule.cron("0 9 * * *")],
)
```

Webhook triggers use `condukt.trigger.webhook(path)`. When a served project has
webhook triggers and Bandit is available, the runtime starts an HTTP listener
and routes `POST` requests to the matching workflow worker.

```python
condukt.workflow(
    name = "triage",
    agent = condukt.agent(model = "openai:gpt-4.1-mini"),
    triggers = [condukt.trigger.webhook(path = "/triage")],
)
```

## Organize reusable Starlark

Keep entrypoints under `workflows/`. Put shared helpers under `lib/` and load
them with relative paths:

```text
my-workflows/
  workflows/
    triage.star
  lib/
    support.star
```

```python
load("../lib/support.star", "support_agent")

condukt.workflow(
    name = "triage",
    agent = support_agent,
    inputs = {"type": "object"},
)
```

Loaded modules are best used for reusable agents, helper functions, constants,
or tool lists. Workflow declarations in loaded modules are evaluated, but only
workflows declared by files under `workflows/` are materialized as project
entrypoints.

## Share workflows

Workflow packages are plain git repositories with a `condukt.toml` at the root
and one or more exported `.star` files.

```text
support-workflows/
  condukt.toml
  lib/
    triage.star
```

`condukt.toml` is required for shared packages:

```toml
name = "support-workflows"
version = "1.0.0"
exports = ["lib/triage.star"]
requires_native = ["starlark", "pubgrub"]

[signatures]
```

Package names are lowercase and hyphenated. Versions are semantic versions.
Exports are relative `.star` paths. Tag the git repository with the same
version:

```sh
git tag v1.0.0
git push origin v1.0.0
```

An exported file should define values that consumers can load:

```python
triage_agent = condukt.agent(
    model = "openai:gpt-4.1-mini",
    system_prompt = "Triage support issues.",
    tools = [condukt.tool("read"), condukt.tool("grep")],
)
```

## Use shared workflows

Consumers use versioned load strings:

```python
load("github.com/you/support-workflows/lib/triage.star@v1.0.0", "triage_agent")

condukt.workflow(
    name = "triage",
    agent = triage_agent,
    inputs = {"type": "object"},
)
```

Non-relative loads must include `@<version>`. Relative loads such as
`./helpers.star` and `../lib/tools.star` stay inside the workspace.
For the common hosted git form, the package identity is
`<host>/<owner>/<repo>` and the rest of the path is the `.star` file inside
that repository. For nested git paths, insert `.git` before the file path:

```python
load("gitlab.com/group/subgroup/support-workflows.git/lib/triage.star@v1.0.0", "triage_agent")
```

Resolve dependencies and write the lockfile:

```sh
mix condukt.workflows.lock --root .
condukt workflows lock --root .
```

Use `--offline` to require the existing lockfile to satisfy every requirement.
Use `--upgrade` when you want resolution to consider newer matching versions.

## The store

Fetched workflow packages are copied into a content-addressed store:

```text
~/.condukt/store/<sha256>/
```

The store key is the deterministic SHA-256 tree hash returned by the workflows
NIF. If fetched contents do not match the expected hash, the store write is
rejected.

The lockfile records the selected package versions and content hashes:

```toml
version = 1

[packages."github.com/tuist/condukt-tools"]
version = "1.2.0"
url = "https://github.com/tuist/condukt-tools"
sha256 = "abcdef..."
integrity = "sha256-base64..."
dependencies = ["github.com/foo/bar"]
```

## Starlark API

See the [Workflow Starlark API](workflow_starlark_api.md) reference for every
available builtin, load target, tool reference, sandbox declaration, and trigger
shape.

## Future hooks

The current subsystem keeps these features out of scope:

* Sigstore verification
* Hosted package discovery
* Dependency mirrors
* Rich secret provider integrations

Those can be added without changing the core file layout, lockfile format, or
runtime ownership model.
