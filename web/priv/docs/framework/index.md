# Build your own agent with Condukt

Condukt is a framework for building agents, not only the coding agent that ships with it. It comes in two implementations that share the same model of what an agent is: an Elixir library for services on the BEAM, and Rust crates with a WebAssembly package for native hosts and browsers.

## Pick your stack

| You are building | Use | Start here |
| --- | --- | --- |
| An agent inside an Elixir or Phoenix application | The `condukt` Hex package | [Elixir library](/framework/elixir) |
| An agent in a web page or a native Rust host | The `condukt` crates and `@tuist/condukt` | [Rust and browser](/framework/rust) |

Both stacks run the same loop: the session owns conversation history and the order of model and tool turns, while the surrounding application owns credentials, tools, isolation, and presentation. Read [architecture](/framework/architecture) once and the vocabulary carries across both.

## What each stack gives you

The Elixir library is the fuller of the two. Agents are OTP processes, so they inherit supervision, streaming, and backpressure from the platform:

- Agents and sub-agents as supervised processes, with typed inputs and outputs.
- [Tools](/framework/elixir/tools) for files, shell, and your own domain, executed through a [sandbox](/framework/elixir/sandbox) rather than the host filesystem.
- [MCP servers](/framework/elixir/mcp) as tool sources, and [HTTP routes](/framework/elixir/http-routes) that expose an agent as a JSON endpoint.
- [Network policy](/framework/elixir/network-policy), [secrets](/framework/elixir/secrets), and [redaction](/framework/elixir/redaction) for agents that run untrusted work.
- [Sessions and persistence](/framework/elixir/sessions-and-persistence), [compaction](/framework/elixir/compaction), and [telemetry](/framework/elixir/telemetry) for long-running conversations.

The Rust side is the portable core. It has no opinion about where inference or tools come from, which is what makes it embeddable:

- A host-driven session that produces completion requests and validates every transition.
- A [host interface](/framework/rust/host-interface) your application drives from any runtime.
- The [`@tuist/condukt`](/framework/rust/browser-package) WebAssembly package for browsers, with [inference](/framework/rust/inference) and [tools](/framework/rust/tools) supplied by the page.
- Focused [crates](/framework/rust/crates) so a host links only what it needs.

## How the coding agent fits

The terminal coding agent is one application built on the Rust crates. It is a useful reference for what a complete host looks like: it owns provider sign-in, workspace tools, cancellation, and presentation, and leaves conversation state to the session. If you want to use it rather than build on it, follow the [coding agent journey](/cli) instead.
