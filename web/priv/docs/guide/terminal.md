# Terminal coding agent

The Condukt CLI combines the portable agent loop with local workspace tools and an interactive conversation in the terminal.

## Interactive mode

Run `condukt` without a subcommand from the project you want to work on:

```sh
condukt
```

The slash menu exposes the same primary workflows as the command line:

| Command | Purpose |
| --- | --- |
| `/connect` | Connect an OpenRouter account or key |
| `/files` | List files at the workspace root |
| `/read <path>` | Read a workspace file |
| `/help` | Show available commands |
| `/quit` | Exit Condukt |

The coding agent can ask for two model tools:

- `read` reads text from a path and truncates very large results.
- `bash` runs a shell command in the workspace with a bounded timeout.

Tool activity appears in the transcript so the user can see how an answer was produced.

## Give Condukt useful context

Start Condukt at the project root so file and command tools use the expected workspace. Describe the desired outcome, relevant constraints, and how the result should be validated.

For example:

```text
Find the failing test, explain the root cause, and propose the smallest safe fix.
```

## Continue elsewhere

Use [editor integration](/guide/editor) when another application should present the conversation. Use [automation](/guide/automation) when you need one non-interactive task.

See the [command-line reference](/reference/command-line) for every terminal option.
