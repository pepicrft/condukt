# Define tools

Tools are the complete set of actions an agent may request from its current host. A browser page, terminal application, and editor can expose different registries while sharing the same Condukt session state.

## Treat the registry as an authority boundary

Register only capabilities appropriate to the current surface and user. A public browser page should not receive filesystem or shell authority merely because the terminal coding agent has those tools.

Each tool needs:

- a unique name;
- a description that tells the model when to use it;
- an argument shape expressed with [JSON Schema](https://json-schema.org/);
- an execution function that returns text for the model.

## Register a browser tool

```js
const tools = [{
  name: "read_page",
  description: "Read the public content on the current page.",
  parameters: {
    type: "object",
    properties: {},
    additionalProperties: false,
  },
  execute: async (_arguments, context) => {
    context.signal.throwIfAborted()
    return document.querySelector("main").innerText.slice(0, 20_000)
  },
}]
```

Pass the registry when creating the agent:

```js
const agent = await createAgent({inference, tools})
```

## Validate every call

Treat model-produced arguments as untrusted input:

1. Reject unknown fields and invalid values.
2. Constrain paths, network destinations, and result sizes.
3. Pass the cancellation signal to `fetch` and other cancellable work.
4. Return a clear error instead of hiding a failed operation.
5. Avoid placing credentials or private state in tool results.

## Return one result per request

When driving the lower-level host session, return exactly one output for every requested tool call and preserve each call identifier. Condukt rejects mismatched or duplicate results so the conversation remains recoverable.

Continue with the [host interface](/framework/rust/host-interface) or inspect the higher-level [browser package](/framework/rust/browser-package).
