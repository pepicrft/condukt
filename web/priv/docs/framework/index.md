# Build your own agent with Condukt

Condukt is an Elixir framework for building agents that do real work on your infrastructure. The agent loop is the easy part of that and the least of what this gives you: every session is a supervised process whose tools run in a sandbox, on a network you decide, with secrets it never gets to print.

Agents here are the imperative half of the picture. A model decides what to do next, turn by turn, which is the right shape when the steps are not known in advance. It composes with a declarative workflow engine rather than replacing one: let the workflow own the steps you can name, and give an agent the ones you cannot.

## Start here

| You are building | Start here |
| --- | --- |
| An agent inside an Elixir or Phoenix application | [Elixir library](/framework/elixir) |
| Your first agent, end to end | [Getting started](/framework/elixir/getting-started) |
| An agent whose loop you drive yourself | [Architecture](/framework/architecture) |

The session owns conversation history and the order of model and tool turns, while the surrounding application owns credentials, tools, isolation, and presentation. Read [architecture](/framework/architecture) once and the vocabulary carries through the rest.

## What you get

- Agents and [sub-agents](/framework/elixir/subagents) as supervised processes, with typed inputs and outputs.
- [Tools](/framework/elixir/tools) for files, shell, and your own domain, executed through a [sandbox](/framework/elixir/sandbox) rather than the host filesystem.
- [MCP servers](/framework/elixir/mcp) as tool sources, and [HTTP routes](/framework/elixir/http-routes) that expose an agent as a JSON endpoint.
- [Network policy](/framework/elixir/network-policy), [secrets](/framework/elixir/secrets), and [redaction](/framework/elixir/redaction) for agents that run untrusted work.
- [Sessions and persistence](/framework/elixir/sessions-and-persistence), [compaction](/framework/elixir/compaction), and [telemetry](/framework/elixir/telemetry) for long-running conversations.

## Agents outside a process

Not every host wants Condukt to own the provider call. `Condukt.HostSession` is the same loop with the caller doing the work: it holds conversation state and says what should happen next, while you perform inference and run tools. No processes, no input or output, no dependencies. Use it when the caller owns the provider call, and `Condukt.Session` when Condukt should.

The terminal on the home page is a version of this idea: the loop runs on the server as a `Condukt.Session`, and its tools run in the visitor's browser, reached back over the LiveView socket. The agent's reach is whatever the page grants it.

## How the coding agent fits

The terminal coding agent is one application built on this library. It is a useful reference for what a complete host looks like: it owns provider sign-in, workspace tools, cancellation, and presentation, and leaves conversation state to the session. If you want to use it rather than build on it, follow the [coding agent journey](/cli) instead.
