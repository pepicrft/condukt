# Build your own agent with Condukt

Condukt provides a portable conversation state machine and agent loop. Your application supplies inference, explicit tools, presentation, and lifecycle.

## Understand the boundary

Start with [how Condukt works](/guide/how-condukt-works). The portable session owns conversation history and validates the order of model and tool turns. The host owns everything with authority outside that state: credentials, network transport, tools, cancellation, and user interface.

## Choose an integration level

| Integration | Start here |
| --- | --- |
| Browser application | Follow the [browser quickstart](/guide/browser) and use the `@tuist/condukt` package. |
| Custom host loop | Implement the [host interface](/reference/host-interface) directly. |
| Native Rust application | Reuse the focused crates described in [Rust crate architecture](/reference/internals). |

## Build a host

1. [Provide inference](/guide/inference) from the model service and credential flow your application chooses.
2. [Define tools](/reference/tools) that expose only the capabilities appropriate to the current surface.
3. Drive each completion and tool step through the [host interface](/reference/host-interface).
4. Present messages and tool activity in your own interface.

## Public boundaries

The [browser package](/reference/browser-package) and host session are supported integration boundaries. Provider-specific translations and generated WebAssembly bindings remain implementation details.
