# Workflow Starlark API

Condukt workflow files are standard Starlark files evaluated with a small
`condukt` builtin. Evaluation returns materialized Elixir maps and lists. No
runtime state is kept in the Starlark heap after loading a project.

This reference documents the Starlark API available to workflow authors.

## Evaluation model

Workflow files live under `workflows/` and use the `.star` extension. Files can
load reusable helpers from relative paths, built-in Condukt modules, or locked
git packages.

```python
load("../lib/support.star", "support_agent")
load("@condukt/tools", "tool")
load("@condukt/sandbox", "local")
```

Relative loads start with `./` or `../` and stay inside the current workspace.
External loads use this grammar:

```text
<host>/<owner>/<repo>/<file>.star@<version>
```

The version is required and must parse as a semantic version after an optional
leading `v` is removed. The package identity for the lockfile is
`<host>/<owner>/<repo>`. The remaining path points to the Starlark file inside
that repository.

For nested repository paths, insert `.git` before the file path so Condukt can
separate the repository URL from the Starlark path:

```python
load("gitlab.com/group/subgroup/support-workflows.git/lib/export.star@v1.0.0", "exported")
```

## Built-in load modules

These load targets are always available:

| Load target | Exports |
| --- | --- |
| `@condukt/tools` | `tool` |
| `@condukt/sandbox` | `local`, `virtual` |

They are aliases for the functions on the `condukt` object:

```python
load("@condukt/tools", "tool")
load("@condukt/sandbox", "local", "virtual")

agent = condukt.agent(
    tools = [tool("read")],
    sandbox = local(cwd = "."),
)
```

## `condukt.workflow`

Declares one runnable workflow.

```python
condukt.workflow(
    name = "triage",
    agent = condukt.agent(...),
    triggers = [],
    inputs = {"type": "object"},
    system_prompt = None,
    model = None,
)
```

| Parameter | Required | Description |
| --- | --- | --- |
| `name` | Yes | Workflow name used by `condukt workflows run <name>` and runtime workers. |
| `agent` | Yes | Agent declaration returned by `condukt.agent`. |
| `triggers` | No | List of trigger declarations. Defaults to `[]`. |
| `inputs` | No | JSON Schema map for invocation input. Defaults to `None`. |
| `system_prompt` | No | Workflow-level prompt override. Defaults to the agent prompt. |
| `model` | No | Workflow-level model override. Defaults to the agent model. |

Workflow names must be non-empty strings. Duplicate workflow names in one
project are rejected.

## `condukt.agent`

Declares the runtime options used when a workflow fires.

```python
agent = condukt.agent(
    model = "openai:gpt-4.1-mini",
    system_prompt = "You triage incoming issues.",
    tools = [condukt.tool("read"), condukt.tool("grep")],
    thinking_level = "medium",
    sandbox = condukt.sandbox.local(cwd = "."),
)
```

| Parameter | Required | Description |
| --- | --- | --- |
| `model` | No | ReqLLM model spec in `provider:model` format. |
| `system_prompt` | No | System prompt passed to the session. |
| `tools` | No | List of tool declarations. Defaults to `[]`. |
| `thinking_level` | No | One of `off`, `minimal`, `low`, `medium`, or `high`. |
| `sandbox` | No | Sandbox declaration. Defaults to a local sandbox rooted at the project. |

## `condukt.tool`

Adds a tool by registry reference.

```python
condukt.tool("read")
condukt.tool("command", command = "gh", env = {"GH_TOKEN": "..."})
```

The first argument is the tool reference. Keyword arguments become tool options.
Options are sorted deterministically and converted to Elixir keyword options.

Built-in tool references:

| Reference | Elixir module |
| --- | --- |
| `read` | `Condukt.Tools.Read` |
| `bash` | `Condukt.Tools.Bash` |
| `edit` | `Condukt.Tools.Edit` |
| `write` | `Condukt.Tools.Write` |
| `glob` | `Condukt.Tools.Glob` |
| `grep` | `Condukt.Tools.Grep` |
| `command` | `Condukt.Tools.Command` |
| `sandbox.virtual.mount` | `Condukt.Sandbox.Virtual.Tools.Mount` |

Unknown references resolve to custom modules under
`Condukt.Workflows.Tools.<CamelCaseRef>`. For example,
`github.review` resolves to `Condukt.Workflows.Tools.GithubReview`.
The module must be available at workflow load time.

## `condukt.sandbox.local`

Runs tools against the host filesystem through `Condukt.Sandbox.Local`.

```python
condukt.sandbox.local(cwd = ".")
```

| Parameter | Required | Description |
| --- | --- | --- |
| `cwd` | No | Working directory. Relative paths are expanded from the workflow project root. |

If no sandbox is supplied, workflows use a local sandbox rooted at the project.

## `condukt.sandbox.virtual`

Runs tools against the in-tree virtual sandbox.

```python
condukt.sandbox.virtual(
    mounts = [
        {"host": ".", "vfs": "/workspace", "mode": "readwrite"},
    ],
)
```

`mounts` defaults to `[]`. Each mount can be a map with `host`, `vfs`, and
optional `mode`, or a list shaped as `[host, vfs]` or `[host, vfs, mode]`.
Known modes are `readonly` and `readwrite`.

## `condukt.schedule.cron`

Adds a cron trigger.

```python
condukt.schedule.cron("0 9 * * *")
```

Cron expressions are parsed by `Crontab.CronExpression.Parser`. The runtime
starts one cron process per cron trigger.

## `condukt.trigger.webhook`

Adds an HTTP webhook trigger.

```python
condukt.trigger.webhook(path = "/triage")
```

Webhook paths are matched by the runtime router. Served workflow projects start
an HTTP listener when at least one webhook trigger exists and Bandit is
available.

## `condukt.secret`

Declares a secret reference.

```python
condukt.secret("GITHUB_TOKEN")
```

The returned value is materialized as data:

```json
{"type": "secret", "name": "GITHUB_TOKEN"}
```

Secret provider integrations are not part of the current runtime. Use this only
when building workflow helpers that expect secret references as data.

## Value conversion

Condukt converts Starlark values to JSON-like Elixir data:

| Starlark value | Elixir data |
| --- | --- |
| `None` | `nil` |
| string | binary |
| bool | boolean |
| int or float | number |
| list or tuple | list |
| dict | map |
| Condukt builtin result | map with `type`, `kind`, or related fields |

This means workflow declarations should use JSON-compatible values for inputs,
tool options, mounts, and trigger data.

## Complete example

```python
load("@condukt/tools", "tool")
load("@condukt/sandbox", "local")

triage_agent = condukt.agent(
    model = "openai:gpt-4.1-mini",
    system_prompt = "Triage incoming issues and return a concise summary.",
    tools = [tool("read"), tool("grep")],
    sandbox = local(cwd = "."),
)

condukt.workflow(
    name = "triage",
    agent = triage_agent,
    triggers = [condukt.trigger.webhook(path = "/triage")],
    inputs = {
        "type": "object",
        "properties": {
            "issue": {"type": "string"},
        },
        "required": ["issue"],
    },
)
```

## Validation

Run validation before sharing or serving workflows:

```sh
condukt workflows check --root .
mix condukt.workflows.check --root .
```

Validation loads the project, checks all materialized workflow declarations,
resolves tool references, validates sandbox kinds, and checks model identifiers.
