# Provide inference

Inference is a service supplied by the host application. The host chooses the provider, model, transport, credential flow, retry policy, and request limits.

## Keep inference outside the session

The portable session produces provider-neutral completion requests. It never reads credentials or performs provider network requests. This lets each application choose a credential flow appropriate to its surface.

## Browser inference

A browser host supplies any object with a `complete(request, context)` function. `createHttpInference` is the included same-origin adapter:

```js
const inference = createHttpInference({
  endpoint: "/api/completions",
  model: "openrouter/auto",
})
```

The endpoint translates the provider-neutral request and returns one assistant message. This makes the page independent of provider-specific authentication.

## Adding another provider

A provider adapter should:

1. Translate Condukt messages and tool definitions into the provider request.
2. Preserve tool call identifiers exactly across responses and results.
3. Return an assistant message in Condukt's provider-neutral protocol.
4. Keep credentials in the host rather than the portable session.
5. Surface provider errors without placing secrets in logs or model-visible text.

Authentication is host-driven because different surfaces have different browser, callback, and credential-storage capabilities.

## Model selection

The host owns the model name. A terminal application may choose a stable default, while an embedding application can select a model for its own latency, capability, or cost requirements.

Continue with [defining tools](/reference/tools) or the lower-level [host interface](/reference/host-interface).
