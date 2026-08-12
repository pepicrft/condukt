# Architecture

Condukt separates the agent state machine from the capabilities owned by an application. The same separation holds in both implementations: the [Elixir library](/framework/elixir) on the BEAM, and the Rust crates behind the terminal coding agent and the browser package.

## The host boundary

Every Condukt surface supplies three things:

1. **Inference** translates a provider-neutral completion request into a model response.
2. **Tools** define the complete set of actions the model may request.
3. **Presentation** turns messages and tool activity into a terminal, editor, browser, or another interface.

The portable session owns message history and the sequence of model and tool turns. It does not own provider credentials, network policy, filesystem access, or shell access.

## One turn through the agent loop

When a user submits a prompt, the session adds it to the conversation and creates a completion request. The host sends that request to its configured inference service.

If the model returns a final answer, the turn completes. If it requests tools, the host executes only tools registered for that surface, returns one result for every request, and asks the model to continue.

```text
user prompt
    ↓
completion request
    ↓
model response ── final text ──→ complete
    │
    └── tool requests ──→ host tools ──→ completion request
```

## Different surfaces, different authority

The terminal host can register tools that read workspace files and run commands. A public web page should usually register narrower capabilities, such as reading public repository content through `fetch` requests.

This boundary prevents a browser build from inheriting terminal authority merely because both surfaces share the same agent loop.

## Provider-neutral state

Completion requests contain messages and tool definitions. Provider adapters translate that shape into the service-specific request and response formats. This keeps provider authentication and transport outside the core session.

For the exact boundary, see the [host interface reference](/framework/rust/host-interface) in Rust, or [agents](/framework/elixir/agents) and [tools](/framework/elixir/tools) in Elixir, where the library drives the loop for you inside a supervised process.
