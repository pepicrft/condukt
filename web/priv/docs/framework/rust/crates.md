# Rust crate architecture

Condukt's Rust surface is a workspace of focused crates that back the browser package. It lives at `packages/condukt/crates/`, next to the npm package it produces. Applications can depend on the narrowest layer that matches the host they are building.

## Foundation crates

| Crate | Responsibility |
| --- | --- |
| `condukt-protocol` | Provider-neutral messages, roles, and tool-call identifiers. |
| `condukt-inference` | Provider and tool-definition traits shared by session implementations. |
| `condukt-session` | Conversation history, host-driven state transitions, and the synchronous native agent loop. |

The host-driven `HostSession` is the portable core used when inference and tools execute outside Rust. It produces a completion request, accepts one assistant response, requests tool outputs when needed, and validates every transition.

## Feature crates

| Crate | Responsibility |
| --- | --- |
| `condukt-wasm` | WebAssembly bindings around the host-driven session. |

Capabilities live outside the portable session rather than inside it. A browser host links `condukt-wasm` and registers only the tools that page should have.

## Where the terminal agent lives

The terminal coding agent is not one of these crates. It is an Elixir application built on the [Elixir library](/framework/elixir), packaged as a single binary per platform. Read [use Condukt as a coding agent](/cli) for it.

## Choose a starting point

- Use `@tuist/condukt` and the [browser quickstart](/framework/rust/browser) for a web application.
- Use `condukt_session::HostSession` and the [host interface](/framework/rust/host-interface) for a custom asynchronous host.
- Use `condukt_session::Session` with an `InferenceProvider` and `ToolDispatcher` for a synchronous native host.

Review [how Condukt works](/framework/architecture) before coupling a new host to a lower-level crate.
