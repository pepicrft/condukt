# Install and connect

Install the Condukt CLI, connect OpenRouter, and run your first coding task.

## Install with mise

Install the latest release globally with [mise](https://mise.jdx.dev/):

```sh
mise use -g "ubi:tuist/condukt[matching=condukt-,exe=condukt]"
```

The release also carries the library's precompiled native artifacts, several of which name the same platform. The `matching=condukt-` filter is what points mise at the agent rather than at one of those.

Confirm that the command is available:

```sh
condukt --help
```

## Install by downloading a binary

Each release attaches one binary per platform, named after its target. Download the one that matches your machine, make it executable, and put it on your path:

```sh
curl -Lo condukt https://github.com/tuist/condukt/releases/latest/download/condukt-aarch64-apple-darwin
chmod +x condukt
```

Binaries are published for macOS on Apple silicon (`aarch64-apple-darwin`) and Intel (`x86_64-apple-darwin`), and for Linux on 64-bit Intel (`x86_64-unknown-linux-musl`) and ARM (`aarch64-unknown-linux-musl`). There is no Windows binary yet. Each one carries its own runtime, so nothing else needs to be installed. Linux binaries are statically linked against musl and run on any distribution.

The first run unpacks the binary into a cache directory, so it takes a moment longer than the ones after it.

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
