# Automation

Use one-shot execution when a script, build job, or another program should submit one coding task without opening the terminal interface.

## Run one task

Pass the prompt directly:

```sh
condukt exec "Run the tests and summarize any failures"
```

Use `--cwd <path>` to select another workspace. When the prompt is omitted, Condukt reads it from standard input:

```sh
printf "Summarize the current changes" | condukt exec
```

## Produce machine-readable output

Use `--json` when another program consumes the final response. The output is encoded as [JavaScript Object Notation](https://www.json.org/json-en.html).

Use `--color never` when logs must not contain terminal color sequences. Add `--verbose` to write tool activity to standard error while keeping the final response on standard output.

## Provide credentials safely

For unattended tasks, set `CONDUKT_OPENROUTER_API_KEY` in the job environment. Avoid placing credentials directly in command history or configuration committed with the project.

Use `CONDUKT_CREDENTIAL_DIR` when parallel jobs need isolated, lock-protected credential storage. Learn more in [providers and credentials](/cli/credentials).

See the [command-line reference](/cli/command-line) for all execution options.
