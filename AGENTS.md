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
- See `web/priv/docs/framework/elixir/sandbox.md` for behaviour shape and how to add custom sandboxes.

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
- See `web/priv/docs/framework/elixir/network-policy.md` for topology, the policy/decider
  model, context shape, telemetry, trust-injection details, and
  limitations. Keep deep architecture there, not here.

## MCP

- Condukt connects to external Model Context Protocol servers as a
  client, exposing each server's tools to agents under `<server>.<tool>`
  ids. See `web/priv/docs/framework/elixir/mcp.md` for transports and auth shapes.
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
- See `web/priv/docs/framework/elixir/subagents.md` for declaration, inheritance, and supervision
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
- See `web/priv/docs/framework/elixir/agents.md` for runtime boundary and callback implications.

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

## Terminal agent (`cli/`)

The terminal coding agent is an Elixir Mix project under `cli/`, application `:condukt_cli`, modules under `Condukt.CLI.*`. It is a layer over the library, not a second agent: it depends on the root project through `{:condukt, path: ".."}`, and the turn loop, tool dispatch, sandboxing, retries, telemetry, and project instructions all come from `Condukt.Session`. The binary is `condukt`.

- Structure: `Condukt.CLI.App` is a pure state machine. Transitions return `{app, effects}`, where an effect is a term like `{:open_browser, url}` or `{:submit_prompt, prompt}`. `Condukt.CLI.TUI` is the only module that owns processes, sockets, and the renderer; it runs those effects. Keep new interface behaviour in `App` so it stays testable without a terminal.
- Rendering: [ex_ratatui](https://hexdocs.pm/ex_ratatui) (`use ExRatatui.App`, callback runtime). Widgets are plain structs rebuilt every frame; `render/2` returns the whole screen as `[{widget, %Rect{}}]`. Key event fields are lowercase strings (`%Event.Key{code: "up", modifiers: ["ctrl"]}`), never atoms.
- Build and check: `cd cli && mix deps.get`, then `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, and `mix test` must all be green. Credo and the formatter use the repository-root `.credo.exs`; `cli/credo` is a symlink to `../credo` so its `requires` resolve with `cli/` as the working directory. Do not add a second `.credo.exs` under `cli/`: two configs in the tree crash Quokka's Credo reader during `mix format`.
- Run it from the checkout with `mix condukt`, `mix condukt exec "..."`, `mix condukt files`. Outside a wrapped binary the supervision-tree entry point is inert, so `mix test` and `iex -S mix` never start the interface.
- Packaging: [Burrito](https://github.com/burrito-elixir/burrito) wraps the release into one self-extracting binary per platform. `MIX_ENV=prod BURRITO_TARGET=<target> mix release --overwrite` writes `cli/burrito_out/condukt_<target>`. Zig 0.16.0 and `xz` must be on `PATH`; the zig version is pinned in `mise.toml` and burrito checks it exactly.
- Targets are `linux`, `linux_arm`, `macos`, and `macos_silicon`. Each is built on a host with the same operating system and CPU, because ex_ratatui's NIF is a precompiled artifact resolved from the build host's triple. Linux also needs `TARGET_ABI=musl`: burrito's linux wrapper runs a musl runtime, and `ExRatatui.Burrito.verify_linux_nif/1` fails the build rather than shipping a glibc library. There is no Windows target; ex_ratatui publishes no Windows artifact.
- Release builds set `CONDUKT_BASHKIT_DISABLE=1` and `CONDUKT_MICROSANDBOX_DISABLE=1`. The terminal agent works in the user's real workspace and never starts those sandboxes, they have no musl artifacts, and a release loads every module at boot, so bundling them would make the linux binary fail to boot rather than merely carry an unused capability.
- Auth: OpenRouter is the only provider today, reached through ReqLLM as `openrouter:<model>`. Credentials live under `$XDG_CONFIG_HOME/condukt` (or `~/.config/condukt`) and can be overridden through `CONDUKT_OPENROUTER_API_KEY` and `CONDUKT_CREDENTIAL_DIR`. Import Pi credentials with `condukt import-pi-credentials`; set `CONDUKT_PI_AUTH_FILE` to override the source path.
- CI: `.github/workflows/condukt-cli.yml` compiles, formats, lints, and tests the agent, builds the linux binary end to end, and covers the browser crates and the WebAssembly package. `.github/workflows/release.yml` builds one binary per target and attaches them to the GitHub release named after their target triple (`condukt-aarch64-apple-darwin` and so on). The same release carries the NIF tarballs, several of which name the same platform, so the documented install is `mise use -g "ubi:tuist/condukt[matching=condukt-,exe=condukt]"`: ubi's `matching` is a tiebreaker among assets that already match the host, and `condukt-` is the prefix only the agent binaries have. Keep that prefix if the artifact naming ever changes.

## Browser package (`packages/condukt/`)

The published npm package `@tuist/condukt` is generated from the `condukt-wasm` Rust crate. The package directory holds the Rust workspace, the TypeScript types, the JavaScript entry point, and the Node tests; the generated `condukt_wasm` artifacts are produced by `wasm-pack` and copied in by the CI workflow and the Dockerfile.

- The Rust workspace lives at `packages/condukt/`, with members `condukt-inference`, `condukt-protocol`, `condukt-session`, and `condukt-wasm`. These crates exist to compile to WebAssembly, which is why they stayed in Rust when the terminal agent moved to Elixir. They are a separate workspace from `native/`; the two share no crates or lockfile.
- Build: `wasm-pack build packages/condukt/crates/condukt-wasm --target web --out-dir "$PWD/packages/condukt/generated" --out-name condukt_wasm --release`, then run `node --test test/*.test.mjs` from `packages/condukt/`. The out-dir must be absolute: `wasm-pack` resolves a relative one against the crate directory, not the working directory.
- `cargo build --all-targets`, `cargo test --all-targets`, `cargo clippy --all-targets --all-features -- --deny warnings`, and `cargo fmt --all -- --check` are all required to be green from `packages/condukt/`.
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

- Source: `web/lib/`, `web/priv/`, `web/assets/`, `web/config/`, `web/test/`. Docs source files live under `web/priv/docs/{cli,framework}/`. Blog posts live under `web/priv/blog/posts/`.
- Package manager: [Hex](https://hex.pm/) for Elixir dependencies; `npm` is not used in the web app.
- Build: `cd web && mix deps.get && mix assets.deploy && mix release`.
- Local preview: `cd web && mix setup && mix phx.server`. The server prints a worktree-specific address; each Git worktree receives a stable suffix from 100 through 999 and uses port `4000 + suffix` plus a database named `condukt_site_dev_SUFFIX`. Tests use `4002 + suffix` and `condukt_site_test_SUFFIX`. Set `CONDUKT_SITE_DEV_INSTANCE` to an unused suffix when an explicit value is useful.
- Deployment: pushes to `main` that touch `web/**`, `cli/**`, `packages/condukt/**`, or `infra/**` publish a Docker image to `ghcr.io/tuist/condukt` and then run `helm upgrade --install` against the production cluster, all in `.github/workflows/condukt-web.yml`. The Dockerfile at `web/Dockerfile` builds the `condukt_site` Phoenix release, the WASM module from `packages/condukt/crates/condukt-wasm`, and the `@tuist/condukt` browser package into the served static assets.
- The site answers `GET /ready` with `ok`. The Kubernetes probes depend on it, so keep the route out of the browser pipeline and free of external dependencies.
- WASM artifacts: the release image bundles `priv/static/condukt/generated/condukt_wasm_bg.wasm` plus the `condukt-wasm` JavaScript glue. The web page imports them as `/condukt/index.js` and `/condukt/generated/condukt_wasm.js`. The esbuild config treats `/condukt/*` as external.
- The web app does not depend on the `condukt` Elixir library. It is a marketing, docs, and browser inference surface only. The hosted Condukt service is not in scope.

## Cluster deployment (`infra/`)

The site runs on Kubernetes and is served at https://condukt.dev.

- `infra/helm/condukt-site/`: the Helm chart (Deployment, Service, Ingress with cert-manager TLS, ExternalSecrets, optional HPA, PDB, and CloudNativePG cluster). `infra/helm/condukt-site/tests/render-conditionals.sh` asserts the conditional paths render; CI lints and runs it on every pull request.
- `infra/k8s/ci-service-account.yaml`: the `condukt-production` namespace and the RBAC for the GitHub Actions deployer, applied by hand once. `infra/k8s/onboarding.md` is the runbook.
- The site is a tenant of the shared `tuist-k8s-production` cluster, not a cluster of its own, in the same way `once-production` is.
- DNS is hand-managed. `condukt.dev` is its own Cloudflare zone, and `platform-external-dns` filters on `tuist.dev`, so it never sees this host and creating the Ingress does not create the record. The apex A record points at the shared ingress LoadBalancer (`91.98.14.217`), DNS only, matching `buildonce.dev`. Do not widen that controller's domain filter or add a second one for `tuist.dev`; it runs `policy=sync` and owns that zone.
- TLS comes from a namespaced `Issuer` (`letsencrypt-condukt`) that the chart ships, solving DNS-01 with a Cloudflare token scoped to `condukt.dev` and synced by ESO from `cloudflare-condukt-dns`. The shared `letsencrypt-cloudflare` ClusterIssuer only holds a `tuist.dev` token and cannot issue for this host; clearing `ingress.issuer` falls back to it for a cluster where it does apply.
- `SECRET_KEY_BASE` is the only required secret. The `onepassword` ClusterSecretStore is pinned to the `tuist-k8s-production` vault, so chart secrets resolve there; the deploy kubeconfig lives in `condukt-k8s-production` and is read by the 1Password CLI in CI. OpenRouter sign-in is PKCE, so no provider credential lives in the cluster.
- The site has no database. `postgres.enabled` is `false` and the app starts its Repo only when `DATABASE_URL` is set; enabling the value provisions the cluster and wires the URL in.
- Verify chart changes with `helm lint infra/helm/condukt-site` and `./infra/helm/condukt-site/tests/render-conditionals.sh` before committing.
- `helm`, `kubectl`, and `jq` are declared in `mise.toml` and pinned by `mise.lock`, like every other tool. Do not pass inline versions (`helm@x.y.z`) in a workflow: change `mise.toml` and run `mise lock --platform linux-x64,macos-arm64`. Workflow steps call `$(mise which helm)` rather than a bare `helm`, because the GitHub runner image ships its own Helm ahead of the mise shim in `PATH`.

## Documentation (`web/priv/docs/`)

All prose documentation has a single source under `web/priv/docs/`, served by the Phoenix site and, for the Elixir pages, published to HexDocs by ExDoc. There is no `guides/` directory.

- `web/priv/docs/cli/`: the terminal coding agent journey ("Use Condukt").
- `web/priv/docs/framework/`: the framework journey ("Build agents"), with `elixir/` for the Hex library and `rust/` for the crates and the browser package.
- The Elixir pages under `web/priv/docs/framework/elixir/` are also the ExDoc extras. They are listed in `mix.exs` under `extras` and `groups_for_extras`, and the root mix `package` includes that directory.
- Cross-link rules: pages that are ExDoc extras link to their siblings with relative Markdown paths (`tools.md`, `sandbox.md#custom`) so both surfaces resolve them. Site-only pages link with root-relative paths (`/framework/rust/browser`), which the site rewrites to `/docs/...`.
- When adding, removing, or meaningfully changing a feature (tools, sessions, compaction, redaction, providers, telemetry, project instructions, streaming, etc.), update the corresponding page in the same change.
- When adding a page, register it in `web/lib/condukt_site_web/docs/navigation.ex`, and, for an Elixir page, in both `extras` and `groups_for_extras` in `mix.exs`. `mix test` in `web/` fails on navigation entries and internal links that point at missing pages.
- Avoid em dashes in documentation prose (use colons, commas, or periods).
- Verify with `mix docs` at the repository root and `mix test` in `web/` before committing.

## Keeping this file up to date

- Whenever a change adds, removes, or meaningfully alters an agent capability, deployment target, or required tool, update this file in the same change. The agent reads `AGENTS.md` at startup and stale entries cause it to act on outdated assumptions.
