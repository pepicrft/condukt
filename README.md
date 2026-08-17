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

Condukt is an Elixir framework for building agents that do real work on your
infrastructure.

The agent loop is the easy part of that and the least of what this gives you.
Every session is a supervised process whose tools run in a sandbox, on a
network you decide, with secrets it never gets to print:

- **Sandboxes** so tools run somewhere other than your filesystem: in memory,
  in a microVM, or in a dedicated Kubernetes pod per session, behind one
  interface.
- **Network policy** per session, audited and enforced outside the agent, with
  allow and deny rules by host and a decider agent for the cases a rule cannot
  settle.
- **Secrets** resolved separately from the conversation and redacted from
  transcripts.
- **OTP** doing what it is good at: supervision, streaming, backpressure,
  cancellation, and sub-agents as children with typed inputs and outputs.

Agents are the imperative half of the picture. They compose with a declarative
workflow engine rather than replacing one: let the workflow own the steps you
can name, and give an agent the ones you cannot.

A marketing and documentation site lives under [`web/`](web/) and serves both
the install story and the public docs. The terminal on its home page runs a
real session on the server and calls its tools in the visitor's browser, which
is the shortest demonstration of the split the library is built around: the
loop is Condukt's, the reach is the host's.

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

## Repository layout

```
condukt/
├── lib/                  # Elixir library
├── native/               # Rust NIFs (bashkit, microsandbox, egress)
├── web/                  # Phoenix marketing site and documentation source
│   └── priv/docs/           # single source for docs and the ExDoc extras
├── infra/                # Helm chart and cluster configuration for the site
└── .github/workflows/    # CI for the library and the web application
```

## Documentation

All documentation lives in `web/priv/docs`. Read it on
[the site](https://condukt.dev/docs), which covers the coding agent and the
Elixir library. The Elixir pages are also
published to [HexDocs](https://hexdocs.pm/condukt/overview.html) alongside the
API reference.

## License

MIT, except the server.

- Everything at the root is MIT: the Elixir library and the Rust native
  implemented functions under `native/`. See [LICENSE](LICENSE).
- [`web/`](web/), the Phoenix server that runs
  [condukt.tuist.dev](https://condukt.tuist.dev), is Mozilla Public License 2.0.
  See [web/LICENSE](web/LICENSE).

A file's licence is the one in the nearest enclosing directory, so nothing you
depend on, embed, or ship carries the server's terms. The documentation under
[`web/priv/docs/`](web/priv/docs) is MIT for the same reason: it is published
with the library.
