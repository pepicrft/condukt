# Browser quickstart

The `@tuist/condukt` package runs Condukt's portable state machine through [WebAssembly](https://webassembly.org/). The web application supplies inference and the complete tool registry.

## Install the package

Add the package from the [npm registry](https://www.npmjs.com/):

```sh
npm install @tuist/condukt
```

## Create an agent

```js
import {createAgent, createHttpInference} from "@tuist/condukt"

const agent = await createAgent({
  inference: createHttpInference({
    endpoint: "/api/completions",
    model: "openrouter/auto",
  }),
  systemPrompt: "Help the developer understand this page.",
  tools: [{
    name: "read_page",
    description: "Read the public content on the page.",
    parameters: {type: "object", properties: {}},
    execute: () => document.querySelector("main").innerText,
  }],
})
```

`createHttpInference` sends provider-neutral completion requests to a same-origin endpoint. The server can own the provider credential so it never enters page JavaScript or WebAssembly memory.

## Run a user turn

`run` is an asynchronous event stream. Render the events that matter to the application:

```js
for await (const event of agent.run("What can I do here?")) {
  if (event.type === "assistant_message") renderMessage(event.message)
  if (event.type === "tool_call") renderToolActivity(event.call)
  if (event.type === "complete") scrollToLatestMessage()
}
```

The same agent instance retains conversation history across turns. Call `free()` when the host no longer needs it.

## Register narrow tools

Browser tools are ordinary asynchronous functions. Treat the registry as an authority boundary:

- Register only capabilities the current page should expose.
- Validate arguments before performing navigation or network requests.
- Limit response sizes before returning content to the model.
- Pass the provided cancellation signal to `fetch` and other cancellable work.

A browser host does not receive filesystem or shell tools unless the application explicitly builds and registers equivalent capabilities.

Next, learn how to [provide inference](/guide/inference), [define explicit tools](/reference/tools), or inspect the complete [browser package reference](/reference/browser-package).
