# Install and connect

Install the Condukt CLI, connect OpenRouter, and run your first coding task.

## Install with mise

Install the latest release globally with [mise](https://mise.jdx.dev/):

```sh
mise use -g github:tuist/condukt
```

Confirm that the command is available:

```sh
condukt --help
```

## Start the terminal agent

Run Condukt from the project you want it to understand:

```sh
cd my-project
condukt
```

Type `/connect`, choose **Sign in with an account**, and follow the OpenRouter flow in your browser. You can choose the application programming interface key option instead when you already have a key.

After connecting, enter a task such as:

```text
Explain the project structure and run the most relevant tests.
```

Condukt can read files and run shell commands from the current workspace. Tool calls remain visible in the conversation.

## Run one task without the interface

Use `exec` from automation or a script:

```sh
condukt exec "Run the tests and summarize any failures"
```

Add `--verbose` to print tool activity to standard error. Add `--json` for a machine-readable result encoded as [JavaScript Object Notation](https://www.json.org/json-en.html).

## Choose your next workflow

- Continue in the [interactive terminal](/cli/terminal).
- Connect Condukt to a [compatible editor](/cli/editor).
- Run repeatable tasks through [automation](/cli/automation).
- Review [providers and credentials](/cli/credentials) before using Condukt unattended.
