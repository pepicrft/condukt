# Rust crate architecture

Condukt is a workspace of focused crates. Applications can depend on the narrowest layer that matches the host they are building.

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
| `condukt-tools` | Native file and shell tools plus their model-visible definitions. |
| `condukt-openrouter` | OpenRouter transport and credential handling for native hosts. |
| `condukt-wasm` | WebAssembly bindings around the host-driven session. |

These crates add capabilities without making them assumptions of the portable session. A browser host can use `condukt-wasm` without linking native file or shell tools.

## Application crate

The `condukt` crate assembles the terminal coding agent, one-shot execution, provider sign-in, workspace tools, rich terminal presentation, and [Agent Client Protocol](https://agentclientprotocol.com/) integration.

Use it as an architectural example when building another application, but keep host-specific policy in your application layer.

## Choose a starting point

- Use `@tuist/condukt` and the [browser quickstart](/framework/rust/browser) for a web application.
- Use `condukt_session::HostSession` and the [host interface](/framework/rust/host-interface) for a custom asynchronous host.
- Use `condukt_session::Session` with an `InferenceProvider` and `ToolDispatcher` for a synchronous native host.

Review [how Condukt works](/framework/architecture) before coupling a new host to a lower-level crate.
