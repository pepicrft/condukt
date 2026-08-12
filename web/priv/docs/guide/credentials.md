# Providers and credentials

The Condukt CLI currently uses OpenRouter for model inference. You can connect interactively, provide a key for one command, or configure an unattended environment.

## Sign in interactively

Run Condukt and open `/connect`. Choose account sign-in to complete the OpenRouter flow in your browser, or enter an application programming interface key you already have.

The saved credential is reused by terminal, editor, and automation workflows.

## Connect from the command line

Save a key without opening the terminal interface:

```sh
condukt connect openrouter --api-key <key>
```

If Pi already has an OpenRouter credential, import it without printing the value:

```sh
condukt import-pi-credentials
```

## Configure unattended jobs

Set the key in the environment:

```sh
export CONDUKT_OPENROUTER_API_KEY=<key>
condukt exec "Run the tests"
```

Use `CONDUKT_CREDENTIAL_DIR` to give a test harness or parallel job an isolated credential directory.

## Storage locations

Credentials follow the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/). Condukt uses `$XDG_CONFIG_HOME/condukt` when configured and otherwise falls back to `~/.config/condukt`.

See [automation](/guide/automation) for non-interactive tasks and the [command-line reference](/reference/command-line) for credential commands.
