# `@tuist/condukt`

Condukt's browser package keeps the agent loop in
[WebAssembly](https://webassembly.org/) and delegates capabilities to its host.
The host supplies two things:

- An inference function. A web application can proxy this through its own
  server so provider credentials never enter JavaScript or WebAssembly memory.
- An explicit tool registry. A browser can expose page context, navigation, or
  application actions without inheriting terminal-only filesystem or shell
  access.

```js
import {createAgent, createHttpInference} from "@tuist/condukt"

const agent = await createAgent({
  inference: createHttpInference({model: "openrouter/auto"}),
  systemPrompt: "Help the developer understand this page.",
  tools: [{
    name: "read_page",
    description: "Read the visible page content.",
    parameters: {type: "object", properties: {}},
    execute: () => ({title: document.title, text: document.querySelector("main").innerText}),
  }],
})

for await (const event of agent.run("What can Condukt do here?")) {
  console.log(event)
}
```

The page chooses both the inference configuration and its tool allowlist. The
generated low-level `AgentSession` binding remains an implementation detail;
the host-driven `createAgent` interface is the supported application boundary.

## Publishing

The repository release workflow builds and tests this package, matches the
Condukt release version, and publishes with registry provenance. Before the
first automated release, claim `@tuist/condukt` and configure `release.yml` as
its trusted GitHub publisher in the [npm package registry](https://www.npmjs.com/).
The workflow uses short-lived publishing identity and does not require a
long-lived registry token.
