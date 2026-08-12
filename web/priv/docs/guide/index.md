# Use Condukt as a coding agent

Condukt works directly in a project from the terminal, through a compatible editor, or as one task in an automation script. The same Elixir library powers the agent loop everywhere, while each host picks the inference provider and the tool registry that fit its environment.

## Start in five minutes

1. [Install the Condukt CLI and connect your provider](/guide/getting-started).
2. Open the project you want Condukt to understand.
3. Run `condukt` and describe the coding task.

The CLI can read project files and run shell commands. It shows tool activity in the conversation so you can follow how it reached an answer.

## Choose how you work

| Workflow | Use it when |
| --- | --- |
| [Terminal coding agent](/guide/terminal) | You want an interactive conversation in the terminal. |
| [Editor integration](/guide/editor) | You want Condukt behind an editor that supports the [Agent Client Protocol](https://agentclientprotocol.com/). |
| [Automation](/guide/automation) | You want one coding task from a script or build job. |

## Configure your provider

The CLI currently connects through OpenRouter. Learn where credentials come from, how interactive sign-in works, and how to keep unattended jobs isolated in [providers and credentials](/guide/credentials).

## Find an exact option

Use the [command-line reference](/reference/command-line) when you already know the workflow and need a flag or subcommand.
