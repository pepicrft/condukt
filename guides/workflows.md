# Workflows

A workflow is a single self-contained Starlark file. The file defines a
top-level `run(inputs)` function and calls `workflow(inputs = ...)` at
module top level to mark itself as runnable. The basename of the file is
the run name.

There is no project layout, manifest, or lockfile. To run a workflow you
point the engine at a path or, in a future slice, a versioned URL.

## A first workflow

`hello.star`:

```python
def run(inputs):
    result = run_cmd(["echo", "Hello, " + inputs["name"]])
    return result["stdout"]

workflow(inputs = {"name": {"type": "string"}})
```

Run it with the standalone engine or with Mix:

```sh
condukt run hello.star --input '{"name": "world"}'
mix condukt.run hello.star --input '{"name": "world"}'
```

The return value of `run(inputs)` is printed on stdout. Strings are
printed as is, other values are JSON-encoded.

## How a workflow runs

The Starlark source is evaluated on a dedicated OS thread. When `run()`
calls a suspending builtin like `run_cmd(...)`, the Starlark VM blocks
while the host runs the side effect, then resumes with the real return
value. From the script's view the call is synchronous: `result` is a
plain Starlark value you can branch on, iterate, or pass to the next
step.

```python
def run(inputs):
    result = run_cmd(["git", "status", "--porcelain"])
    if result["stdout"].strip() == "":
        return "clean"
    else:
        return "dirty"

workflow(inputs = {})
```

`if` and `for` work over real step output. There is no graph of step
references, no template strings, and no `${{ ... }}` syntax.

## Builtins

Top-level builtins available in a workflow file:

- `workflow(inputs = ...)`: marks the file as a runnable workflow.
  Required exactly once at module top level.
- `run_cmd(argv, cwd = None, env = None)`: runs an executable on the
  host. Returns a dict with `ok`, `stdout`, and `exit_code`. `argv` must
  be a list of strings. `cwd` defaults to the workflow's working
  directory. `env` is an optional dict of additional environment
  variables.

Future slices will add `agent`, `http`, `tool`, `parallel_map`, and the
configuration namespace (`condukt.trigger.webhook`,
`condukt.schedule.cron`, `condukt.sandbox.local`).

## Validating a workflow

`condukt check PATH` (or `mix condukt.check PATH`) parses the file and
reports any static problems without executing it:

```sh
condukt check review-pr.star
```

Use it in CI or as part of an LLM authoring loop: generate, check,
fix, repeat.

## What Starlark does not have

Workflows execute in standard Starlark, which is a deterministic Python
subset. Things to remember when writing a workflow:

- No `try`/`except`. Builtins return structured `ok`/`error` values; you
  branch on those.
- No `while` loops and no recursion. Use `for` over a finite iterable.
- No f-strings. Use `+` concatenation or `"...{}".format(...)`.
- Lambdas are single-expression. For multi-statement parallel work, the
  `parallel_map(items, fn)` builtin (future slice) takes a regular `def`
  function.
- No imports beyond `load("...", "name")` of other Starlark files.

These constraints make workflows safe to load from arbitrary URLs and
make `condukt check` able to catch most mistakes statically.

## Future direction

These features are planned but not yet implemented:

- `agent(model = ..., tools = ..., input = ...)` for LLM-driven steps.
- `http(method, url, headers, body)` for deterministic API calls.
- `tool("read")`, `tool("grep")`, etc.: tool references usable by
  `agent`.
- `parallel_map(items, fn)` for fan-out.
- Remote `load(...)` of versioned helpers from
  `github.com/owner/repo/path/file.star@v1.0.0`.
- Optional `--lock` mode that records SHA-256 per fetched URL and
  verifies on later runs (Deno-style integrity).
- Triggers (`condukt.trigger.webhook`, `condukt.schedule.cron`) and
  `condukt serve PATH` to host webhook and cron-driven runs.
