# Command-line reference

## `condukt`

Start the interactive terminal coding agent in the current directory.

```sh
condukt
```

Use `-p` or `--prompt` to submit one task without opening the interface:

```sh
condukt -p "Review the current changes"
```

Use `-h` or `--help` for a summary of every command, and `--version` for the installed version:

```sh
condukt --help
condukt --version
```

## `condukt exec`

Run one coding task and print the final response.

```text
condukt exec [OPTIONS] [PROMPT]
```

| Option | Meaning |
| --- | --- |
| `--api-key <KEY>` | Use an OpenRouter key for this invocation |
| `--cwd <PATH>` | Run tools from another directory |
| `-v`, `--verbose` | Print tool activity to standard error |
| `--json` | Print a machine-readable final response |
| `--color <auto|always|never>` | Control terminal color |

When `PROMPT` is omitted, Condukt reads it from standard input.

## `condukt connect`

Save an OpenRouter key for later terminal and headless sessions:

```sh
condukt connect openrouter --api-key <KEY>
```

Prefer `CONDUKT_OPENROUTER_API_KEY` for unattended scripts so the key is not present in shell history.

## `condukt import-pi-credentials`

Import Pi's saved OpenRouter credential without printing it:

```sh
condukt import-pi-credentials
```

## `condukt files`

List the files at the workspace root, matching the interactive `/files` command:

```sh
condukt files
condukt files --cwd path/to/project
```

## `condukt read`

Print a workspace file, matching the interactive `/read` command. Relative paths resolve against the workspace root, and long files are truncated:

```sh
condukt read README.md
condukt read src/main.ex --cwd path/to/project
```

## `condukt acp`

Run Condukt as an [Agent Client Protocol](https://agentclientprotocol.com/) server over standard input and output:

```sh
condukt acp
```

The client provides the workspace root. Connect OpenRouter before starting the server.
