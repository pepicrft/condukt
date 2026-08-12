# AGENTS.md

## Command Execution

- For running bash commands from Elixir, use `MuonTrap` instead of `System`.
- Prefer `MuonTrap` because it propagates process shutdowns to child processes.
- Reference: https://hexdocs.pm/muontrap/readme.html

## Sandboxes

- Tools that read/write files or run subprocesses must route through the
  `Condukt.Sandbox.*` facade, not `File.*` / `MuonTrap.cmd/3` directly. The
  sandbox is in `context.sandbox` when the tool's `call/2` is invoked.
- Session secrets are resolved through `Condukt.Secrets` and exposed to tools
  through `context.secrets`; command tools should use `Condukt.Secrets.env/1`
  or `Condukt.Secrets.merge_env/2` instead of reading provider-specific secret
  stores directly.
- `Condukt.Sandbox.Local` is the default and operates against the host
  filesystem. `Condukt.Sandbox.Virtual` is in-tree and routes through a
  Rust NIF wrapping bashkit for in-memory virtual filesystem isolation.
  `Condukt.Sandbox.Microsandbox` is in-tree and routes through a Rust
  NIF wrapping the `microsandbox` crate for microVM-backed execution
  against bind-mounted host workspaces. Runtime `mount/3` is not
  supported there; use init-time `:mounts`. `Condukt.Sandbox.Kubernetes`
  runs each session in a dedicated pod via the `:k8s` library;
  idempotent on a stable `:id` so an Oban-style worker can reattach the
  same pod across job retries. K8s sandboxes refresh a heartbeat
  annotation for stale-pod reaping, support `reap_stale/1`, stream
  writes through exec stdin, and can clone an init-time
  `:workspace_source` git repository when the image includes `git`.
- `Condukt.Tools.Command` is the explicit exception: it runs a host-allowlisted
  executable directly, by design, and is not sandbox-routed.
- See `guides/sandbox.md` for behaviour shape and how to add custom sandboxes.

## Network Policy

- `Condukt.Sandbox.NetworkPolicy` is the per-session egress audit +
  policy layer. Set it via `network_policy:` on the
  `Condukt.Sandbox.Kubernetes` spec; other sandboxes ignore the
  option (no enforcement plane).
- `rules` is a keyword list walked top to bottom: `allow:`/`deny:`
  host globs and `decide:` callable (2-arity fun, `{mod, fun}`, a
  module, or `{mod, opts}`). Decide tuning is scoped to the rule:
  `decide: [call: callable, timeout:, cache:, context_messages:,
  context_metadata:]`. The struct itself only carries `:rules`,
  `:default`, `:redact`, `:max_body_capture`.
  `...NetworkPolicy.AgentDecider` wraps a `Condukt` agent and injects
  the decision contract as the agent's `:output` schema; do not
  describe the wire format in the agent prompt.
- A `:decide` rule needs the BEAM<->sidecar control channel: a
  `pods/portforward` WebSocket (`...K8s.PortForward` ->
  `...K8s.ControlBridge`). `ControlBridge` is one per session,
  supervised as a `:transient` child of a `DynamicSupervisor`
  (registered name from `Condukt.Application.control_channel_supervisor/0`)
  under the app root: the standard dynamic-children pattern, not
  start_linked from the session. It monitors the session owner and
  stops `:normal` when the owner goes away (dropped, not restarted: no
  orphaned socket; not linked to the session so no cascade either
  way); a crash is restarted; an unreachable control port retries with
  backoff then gives up `:normal` (no crash-loop). Requires WebSocket
  port-forward (Kubernetes >= 1.30, KEP-4006) and the
  `pods/portforward` RBAC verb; `allow`/`deny`-only policies do not.
  There is no `condukt-egress` control-bridge subcommand.
- The Rust sidecar lives under `native/condukt_egress/` (one binary,
  `netfilter-setup` + `proxy` subcommands; toolchain pinned in its
  `rust-toolchain.toml`; image `ghcr.io/tuist/condukt-egress:<version>`
  built by `.github/workflows/release.yml`, overridable per-spec via
  `:network_policy_image`). Its Dockerfile build is verified on every
  PR by `.github/workflows/condukt-egress.yml`. Workspace MITM trust
  is injected by the pod spec with no image preparation (Java
  keystores excepted).
- See `guides/network_policy.md` for topology, the policy/decider
  model, context shape, telemetry, trust-injection details, and
  limitations. Keep deep architecture there, not here.

## MCP

- Condukt connects to external Model Context Protocol servers as a
  client, exposing each server's tools to agents under `<server>.<tool>`
  ids. See `guides/mcp.md` for transports and auth shapes.
- Three transports are supported: `stdio` (subprocess + newline JSON-RPC),
  `http_sse` (legacy 2024-11 HTTP+SSE), and `streamable_http` (2025-03-26).
  No MCP server mode in v1.
- Stdio MCP subprocesses are NOT routed through `Condukt.Sandbox` for
  the same reason `Condukt.Tools.Command` is exempt: the binary is
  selected by the operator, not by the model. `Condukt.MCP.Transport.Stdio`
  uses `Port.open` directly with bidirectional binary streaming.
- Bearer auth values are not auto-registered as session secrets. If a
  caller wants the value redacted from transcripts, declare it under
  `:secrets` as well.
- Interactive OAuth is intentionally out of scope. The library accepts
  bearer tokens or `client_credentials` grants resolved through
  `Condukt.Secrets`-shaped refs.

## HTTP routes

- Module-defined one-shot agents and statically declared `operation/2`
  entrypoints can be exposed as JSON POST endpoints with `Condukt.Plug` or
  `Condukt.Plug`.
- Plug routers mount `Condukt.Plug` directly with `to: Condukt.Plug` and
  `init_opts:`. Pass `agent:` for normal one-shot agents and add `operation:`
  for typed operation routes.
- Agent route requests may use a raw prompt body, a JSON string body, or a JSON
  object with an optional `"prompt"` string. If omitted, the route's `:prompt`
  option is used, then an empty prompt.
- Operation route requests must be JSON objects matching the operation input
  schema. Responses are JSON envelopes shaped as
  `%{ok: true, result: result}` or
  `%{ok: false, error: %{code: code, message: message}}`.

## Sub-agents

- Agents can declare `subagents/0` as `role: AgentModule` or
  `role: {AgentModule, opts}`. They can also use `role: [opts]` to create an
  anonymous child agent backed by `Condukt.AnonymousAgent`. Sessions
  auto-inject `Condukt.Tools.Subagent` when roles are registered.
- Role opts can declare optional `:input`/`:input_schema` and
  `:output`/`:output_schema` JSON Schemas. Only fields listed in `required`
  are required.
- Child sessions inherit the parent `:sandbox`, `:cwd`, `:model`,
  `:thinking_level`, `:api_key`, `:base_url`, and resolved `:secrets` unless
  those values are overridden in the role registration opts.
- See `guides/subagents.md` for declaration, inheritance, and supervision
  details.

## Agent runtimes

- Agents can be declared with `use Condukt.Agent, runtime: RuntimeModule` or
  `runtime: {RuntimeModule, opts}`. The default runtime is
  `Condukt.AgentRuntimes.Native`, where `Condukt.Session` drives the ReqLLM
  turn and tool loop.
- Non-native runtime modules implement `Condukt.AgentRuntime.run/3`. Condukt
  still owns session identity, sandbox setup, secret resolution, project
  instructions, telemetry, and sub-agent boundaries.
- Built-in SDK runtime adapters are `Condukt.AgentRuntimes.Codex`, which shells
  out to `codex exec`, and `Condukt.AgentRuntimes.Claude`, which shells out to
  `claude --print`. Both use `MuonTrap`, the session cwd, and resolved session
  secrets.
- Treat `model/0`, `thinking_level/0`, `tools/0`, `mcp_servers/0`, and
  native tool-loop callbacks as native-only unless a runtime adapter documents
  an explicit mapping. Use `system_prompt/0` for durable guidance to
  runtime-backed agents; Condukt passes the composed prompt to the runtime.
- See `guides/agents.md` for runtime boundary and callback implications.

## Native NIFs

- `native/condukt_bashkit/` wraps the bashkit virtual sandbox into a
  NIF. Build it with `cd native/condukt_bashkit && cargo build --release`
  or via `MIX_ENV=dev mix compile`.
- `native/condukt_microsandbox/` wraps the `microsandbox` crate into a
  NIF for `Condukt.Sandbox.Microsandbox`. Build it with
  `cd native/condukt_microsandbox && cargo build --release` or via
  `MIX_ENV=dev mix compile`.
- Toolchain: Rust 1.94.x, pinned in each crate's `rust-toolchain.toml`
  and in `mise.toml`.
- `mix compile` source-builds both NIFs in `MIX_ENV=dev`. Other Mix
  environments download the precompiled artifacts from the GitHub release
  when the target is supported.
- The release publish job runs with `MIX_ENV=prod` so Hex package
  validation and publishing exercise the precompiled NIF path.
- Releases must publish precompiled artifacts for every target listed in
  `lib/condukt/bashkit/nif.ex` and `lib/condukt/microsandbox/nif.ex`,
  plus checksum files named `checksum-Elixir.Condukt.Bashkit.NIF.exs`
  and `checksum-Elixir.Condukt.Microsandbox.NIF.exs` in the package
  source. See `.github/workflows/release.yml` for the build matrix.

## Terminal CLI (`cli/`)

The terminal coding agent is a Rust workspace under `cli/`. The binary is `condukt`; the workspace members are `condukt`, `condukt-inference`, `condukt-openrouter`, `condukt-protocol`, `condukt-session`, `condukt-tools`, and `condukt-wasm`.

- Build: `cd cli && cargo build --all-targets`. `cargo test --all-targets`, `cargo clippy --all-targets --all-features -- --deny warnings`, and `cargo fmt --all -- --check` are all required to be green.
- Toolchain: Rust 1.91 (pinned in `cli/rust-toolchain.toml` and `mise.toml`). The CLI is a separate workspace from `native/`; the two share no crates or lockfile.
- Auth: the CLI uses OpenRouter as its only inference provider today. Credentials are stored under `$XDG_CONFIG_HOME/condukt` (or `~/.config/condukt`) and can be overridden through `CONDUKT_OPENROUTER_API_KEY` and `CONDUKT_CREDENTIAL_DIR`. Import Pi credentials with `condukt import-pi-credentials`; set `CONDUKT_PI_AUTH_FILE` to override the source path.
- Wire protocol: the Rust CLI and the Elixir library share the same provider-neutral `Message` and `ToolDefinition` shape (`condukt-protocol`). The hosted `RemoteSession` driver is a follow-up; the CLI defaults to a local driver in-process.
- CI: `.github/workflows/condukt-cli.yml` runs build, test, clippy, fmt, and the WebAssembly package build on every PR that touches `cli/` or `packages/condukt/`.

## Browser package (`packages/condukt/`)

The published npm package `@tuist/condukt` is generated from the `condukt-wasm` Rust crate. The package directory holds the TypeScript types, the JavaScript entry point, and the Node tests; the generated `condukt_wasm` artifacts are produced by `wasm-pack` and copied in by the CI workflow and the Dockerfile.

- Build: `wasm-pack build cli/crates/condukt-wasm --target web --out-dir packages/condukt/generated --release`, then run `node --test test/*.test.mjs` from `packages/condukt/`.
- The Phoenix web app serves the generated files from `priv/static/condukt/`. The page imports `/condukt/index.js` to obtain `createAgent` and `createHttpInference`.

## Git

- After every change, create a git commit and push it to the current branch.

## Elixir

- Condukt supports module-defined one-shot runs with
  `Condukt.run(MyApp.Agent, prompt, opts)`. Prefer this form for synchronous
  work that does not need conversation history. Use `start_link/1` and a
  persistent session only when the caller needs state, streaming, persistence,
  supervision, or multiple turns against the same process.
- Do not type Elixir code by hand when avoidable. Prefer structural edits and tool-assisted changes.
- Do not introduce `try`/`catch` or `rescue` patterns in production Elixir
  code. Prefer tuple-returning APIs and explicit pattern matching. If a
  boundary genuinely needs non-local failure handling, use an existing project
  abstraction or add one deliberately instead of catching locally.
- Tests must not mutate global process state such as `System.put_env/2`,
  `System.delete_env/1`, `Application.put_env/3`, or
  `Application.delete_env/2`. Prefer explicit dependency injection, per-test
  processes, unique temporary paths, and local options so affected tests can run
  with `async: true`.

## Marketing site (`web/`)

The marketing site, public docs, and browser inference endpoint live under `web/` as a Phoenix application named `condukt_site` (modules under `ConduktSite.*`). It serves the install story, hosts the documentation pages, and proxies the browser-side agent through a same-origin `/api/completions` endpoint.

- Source: `web/lib/`, `web/priv/`, `web/assets/`, `web/config/`, `web/test/`. Docs source files live under `web/priv/docs/{guide,reference}/`. Blog posts live under `web/priv/blog/posts/`.
- Package manager: [Hex](https://hex.pm/) for Elixir dependencies; `npm` is not used in the web app.
- Build: `cd web && mix deps.get && mix assets.deploy && mix release`.
- Local preview: `cd web && mix setup && mix phx.server`. The server prints a worktree-specific address; each Git worktree receives a stable suffix from 100 through 999 and uses port `4000 + suffix` plus a database named `condukt_site_dev_SUFFIX`. Tests use `4002 + suffix` and `condukt_site_test_SUFFIX`. Set `CONDUKT_SITE_DEV_INSTANCE` to an unused suffix when an explicit value is useful.
- Deployment: pushes to `main` that touch `web/**` publish a Docker image to `ghcr.io/tuist/condukt-site` with immutable commit and `latest` tags via `.github/workflows/condukt-web.yml`. The Dockerfile at `web/Dockerfile` builds the `condukt_site` Phoenix release, the WASM module from `cli/crates/condukt-wasm`, and the `@tuist/condukt` browser package into the served static assets.
- WASM artifacts: the release image bundles `priv/static/condukt/generated/condukt_wasm_bg.wasm` plus the `condukt-wasm` JavaScript glue. The web page imports them as `/condukt/index.js` and `/condukt/generated/condukt_wasm.js`. The esbuild config treats `/condukt/*` as external.
- The web app does not depend on the `condukt` Elixir library. It is a marketing, docs, and browser inference surface only. The hosted Condukt service is not in scope.

## Documentation (`guides/`)

Per-feature ExDoc pages live under `guides/` and are wired into `mix.exs` via `extras` and `groups_for_extras`. They are published to HexDocs alongside the API reference.

- When adding, removing, or meaningfully changing a feature (tools, sessions, compaction, redaction, providers, telemetry, project instructions, streaming, etc.), update the corresponding page under `guides/` in the same change.
- When introducing a new top-level feature, add a new guide page and register it in both `extras` and `groups_for_extras` in `mix.exs`.
- Avoid em dashes in guide prose (use colons, commas, or periods).
- Verify with `mix docs` before committing.

## Keeping this file up to date

- Whenever a change adds, removes, or meaningfully alters an agent capability, deployment target, or required tool, update this file in the same change. The agent reads `AGENTS.md` at startup and stale entries cause it to act on outdated assumptions.
