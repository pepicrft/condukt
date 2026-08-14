# Use Condukt as a coding agent

Condukt works directly in a project from the terminal, through a compatible editor, or as one task in an automation script. The coding agent is a single Rust binary built on Condukt's own agent loop, so the workflows below share one conversation model and one tool registry.

## Start in five minutes

1. [Install the Condukt CLI and connect your provider](/cli/getting-started).
2. Open the project you want Condukt to understand.
3. Run `condukt` and describe the coding task.

The CLI can read project files and run shell commands. It shows tool activity in the conversation so you can follow how it reached an answer.

## Choose how you work

| Workflow | Use it when |
| --- | --- |
| [Terminal coding agent](/cli/terminal) | You want an interactive conversation in the terminal. |
| [Editor integration](/cli/editor) | You want Condukt behind an editor that supports the [Agent Client Protocol](https://agentclientprotocol.com/). |
| [Automation](/cli/automation) | You want one coding task from a script or build job. |

## Configure your provider

The CLI currently connects through OpenRouter. Learn where credentials come from, how interactive sign-in works, and how to keep unattended jobs isolated in [providers and credentials](/cli/credentials).

## Find an exact option

Use the [command-line reference](/cli/command-line) when you already know the workflow and need a flag or subcommand.

If you want to build an agent of your own rather than use this one, follow the [framework journey](/framework) instead.
