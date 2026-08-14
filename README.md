<p align="center">
  <img src="docs/assets/readme-header.png" alt="Condukt header" width="300" />
</p>

<p align="center">
  <a href="https://hex.pm/packages/condukt"><img src="https://img.shields.io/hexpm/v/condukt.svg" alt="Hex.pm" /></a>
  <a href="https://hexdocs.pm/condukt/"><img src="https://img.shields.io/badge/docs-hexdocs-blue.svg" alt="HexDocs" /></a>
  <a href="https://github.com/tuist/condukt/actions/workflows/condukt.yml"><img src="https://github.com/tuist/condukt/actions/workflows/condukt.yml/badge.svg" alt="CI" /></a>
  <a href="https://hex.pm/packages/condukt"><img src="https://img.shields.io/hexpm/dt/condukt.svg" alt="Hex.pm downloads" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/hexpm/l/condukt.svg" alt="License" /></a>
  <a href="https://github.com/tuist/condukt/stargazers"><img src="https://img.shields.io/github/stars/tuist/condukt?style=flat" alt="GitHub stars" /></a>
  <a href="https://github.com/tuist/condukt/commits/main"><img src="https://img.shields.io/github/last-commit/tuist/condukt.svg" alt="Last commit" /></a>
</p>

Condukt is a cross-platform agent framework and coding agent.

It ships as three surfaces from one repository:

- An **Elixir library** for OTP-native agents with sub-agents, MCP, sandboxes,
  network policy, redaction, compaction, and HTTP routes.
- A **terminal CLI** that runs the same agent loop in Rust with a ratatui TUI,
  slash commands, an ACP backend, and headless `exec` for scripts and CI.
- A **browser package** (`@tuist/condukt`) that ships the portable session as
  WebAssembly so any page can host an agent that only inherits the tools it
  explicitly registers.

A marketing and documentation site lives under [`web/`](web/) and serves both
the install story and the public docs. The same `Message` history and
`ToolDefinition` shape crosses every surface, so the same conversation can move
between them when a host chooses to do so.

## Library

Use Condukt when agents should live inside your OTP system. Add it to
`mix.exs`:

```elixir
def deps do
  [
    {:condukt, "~> 1.5"}
  ]
end
```

```elixir
defmodule MyApp.ProjectAgent do
  use Condukt

  @impl true
  def model, do: "anthropic:claude-sonnet-4-20250514"

  @impl true
  def system_prompt do
    "You help maintain this repository. Prefer concrete findings and patches."
  end

  @impl true
  def tools, do: Condukt.Tools.coding_tools()

  operation :release_notes,
    input: %{
      type: "object",
      properties: %{version: %{type: "string"}},
      required: ["version"]
    },
    output: %{
      type: "object",
      properties: %{
        title: %{type: "string"},
        highlights: %{type: "array", items: %{type: "string"}}
      },
      required: ["title", "highlights"]
    },
    instructions: "Draft release notes from the git history and project files."
end
```

Read the [library documentation on HexDocs](https://hexdocs.pm/condukt/overview.html).

## CLI

Install the terminal coding agent globally with [mise](https://mise.jdx.dev/):

```sh
mise use -g github:tuist/condukt
```

Run `condukt`, then type `/connect` and follow the sign-in flow. Once
connected, type a request and press Enter. Use `/` to browse the available
commands. If you already signed in to Pi with OpenRouter, import its access
credential without printing it:

```sh
condukt import-pi-credentials
```

For scripts and continuous integration, run one task without the terminal
interface:

```sh
condukt exec "Run the test suite and summarize any failures"
```

`condukt -p "..."` is a shorthand, and a prompt can also arrive on standard
input. The command uses the saved OpenRouter credential, or
`CONDUKT_OPENROUTER_API_KEY` when set. Pass `--verbose` to show tool activity
on standard error and `--json` for a machine-readable final response.

## Browser

Add the npm package to a JavaScript or TypeScript application:

```sh
npm install @tuist/condukt
```

```js
import {createAgent, createHttpInference} from "@tuist/condukt"

const agent = await createAgent({
  inference: createHttpInference({model: "openrouter/auto"}),
  tools: [{
    name: "read_page",
    description: "Read the public content on this page",
    parameters: {type: "object", properties: {}},
    execute: () => document.querySelector("main").innerText,
  }],
})
```

The page supplies both the inference configuration and the tool allowlist. The
public Condukt site demonstrates the same package against a Phoenix endpoint
that signs developers in with OpenRouter and proxies the completion request.

## Repository layout

```
condukt/
├── lib/                  # Elixir library
├── native/               # Rust NIFs (bashkit, microsandbox, egress)
├── cli/                  # Rust workspace for the terminal CLI
│   └── crates/
│       ├── condukt/         # binary
│       ├── condukt-inference/
│       ├── condukt-openrouter/
│       ├── condukt-protocol/
│       ├── condukt-session/
│       ├── condukt-tools/
│       └── condukt-wasm/
├── web/                  # Phoenix marketing site, documentation source, browser endpoint
│   └── priv/docs/           # single source for docs and the ExDoc extras
├── packages/condukt/     # @tuist/condukt npm package
├── infra/                # Helm chart and cluster configuration for the site
└── .github/workflows/    # CI for library, CLI, and web
```

## Documentation

All documentation lives in `web/priv/docs`. Read it on
[the site](https://condukt.tuist.dev/docs), which covers the coding agent, the
Elixir library, and the Rust and browser surfaces. The Elixir pages are also
published to [HexDocs](https://hexdocs.pm/condukt/overview.html) alongside the
API reference.

## License

MIT License. See [LICENSE](LICENSE) for details.
