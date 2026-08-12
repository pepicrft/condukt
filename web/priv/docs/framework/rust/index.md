# Rust and browser

The Rust implementation is Condukt's portable core. A session owns conversation history and the order of model and tool turns; the host supplies inference, tools, presentation, and lifecycle. The same session runs in a native binary and, through WebAssembly, in a web page.

## Choose an integration level

| Integration | Start here |
| --- | --- |
| Web application | Follow the [browser quickstart](/framework/rust/browser) and use the `@tuist/condukt` package. |
| Custom host loop | Drive the [host interface](/framework/rust/host-interface) directly from your own runtime. |
| Native Rust application | Reuse the focused crates described in [crate architecture](/framework/rust/crates). |

## Build a host

1. [Provide inference](/framework/rust/inference) from the model service and credential flow your application chooses.
2. [Define tools](/framework/rust/tools) that expose only the capabilities appropriate to the current surface.
3. Drive each completion and tool step through the [host interface](/framework/rust/host-interface).
4. Present messages and tool activity in your own interface.

## Public boundaries

The [browser package](/framework/rust/browser-package) and the host session are supported integration boundaries. Provider-specific translations and generated WebAssembly bindings remain implementation details.

If you are building on the BEAM instead, the [Elixir library](/framework/elixir) covers the same loop with tools, sandboxes, sub-agents, and supervision included.
