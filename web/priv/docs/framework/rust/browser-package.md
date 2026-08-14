# Browser package reference

Package: `@tuist/condukt`

## `initialize(moduleOrPath?)`

Load the WebAssembly module. Initialization is shared across agents created by the same JavaScript module instance.

Pass a request, uniform resource locator, or compiled `WebAssembly.Module` when the application serves the binary from a custom location.

## `createAgent(options)`

Create a provider-neutral agent.

```js
const agent = await createAgent({
  inference,
  tools,
  systemPrompt,
})
```

| Option | Required | Description |
| --- | --- | --- |
| `inference` | Yes | Object with a `complete(request, context)` function |
| `tools` | No | Explicit tool allowlist for this host |
| `systemPrompt` | No | Host operating instructions placed first in history |

Tool names must be unique. Every tool needs a name and an `execute(arguments, context)` function.

## `agent.run(prompt, options?)`

Run one user turn and yield semantic events:

| Event | Meaning |
| --- | --- |
| `assistant_message` | Model text produced during the turn |
| `tool_call` | Tool requested by the model |
| `tool_result` | Tool output returned to the session |
| `complete` | Final assistant response for the turn |

Pass an `AbortSignal` as `options.signal` to cancel inference and tool execution.

## `agent.history()`

Return the current provider-neutral message history.

## `agent.free()`

Release the WebAssembly session. Do not call other agent methods afterward.

## `createHttpInference(options?)`

Create a same-origin inference adapter.

| Option | Default | Description |
| --- | --- | --- |
| `endpoint` | `/api/completions` | Completion endpoint owned by the host application |
| `model` | Host default | Model override added to requests |
| `fetch` | `globalThis.fetch` | Custom request implementation for tests or another runtime |

The adapter includes the page's cross-site request forgery token when a matching metadata element is present.
