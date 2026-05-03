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
- `Condukt.Tools.Command` is the explicit exception: it runs a host-allowlisted
  executable directly, by design, and is not sandbox-routed.
- See `guides/sandbox.md` for behaviour shape and how to add custom sandboxes.

## Native NIF (`native/condukt_bashkit/`)

- The `condukt_bashkit` Rust crate wraps the bashkit virtual sandbox into
  a NIF. Build it with `cd native/condukt_bashkit && cargo build --release`
  or via `MIX_ENV=dev mix compile`.
- Toolchain: Rust 1.94.x, pinned in `native/condukt_bashkit/rust-toolchain.toml`
  (also in `mise.toml`).
- `mix compile` source-builds the NIF in `MIX_ENV=dev`. Other Mix
  environments download the precompiled NIF from the GitHub release.
- The release publish job runs with `MIX_ENV=prod` so Hex package validation
  and publishing exercise the precompiled NIF path.
- Releases must publish precompiled artifacts for every target listed in
  `lib/condukt/bashkit/nif.ex`'s `:targets` option, plus a checksum file
  named `checksum-Elixir.Condukt.Bashkit.NIF.exs` in the package source.
  See `.github/workflows/release.yml` for the build matrix.

## Workflows

- `Condukt.Workflows` loads Starlark workflow declarations from a project root,
  resolves package loads through a TOML lockfile, materializes Elixir structs,
  and starts caller-owned runtimes for manual, cron, and webhook-triggered
  runs.
- The workflows NIF lives in `native/condukt_workflows/`. It evaluates
  Starlark, runs PubGrub resolution, and computes deterministic SHA-256 tree
  hashes. It must return materialized Elixir maps and lists, not pointers into
  Starlark heap state.
- Workflow package identity uses versioned load strings:
  `<host>/<path>@<version>`. Non-relative loads require a version. Relative
  loads stay inside the workspace.
- Shared packages are stored under `~/.condukt/store/<sha256>/`. Store writes
  must verify `Condukt.Workflows.NIF.sha256_tree/1` before the atomic rename.
- `condukt.lock` is TOML, committed, deterministic, and offline-first. Use
  `mix condukt.workflows.lock` to update it.
- Workflow runtimes are not auto-started by `Condukt.Application`. Callers use
  `Condukt.Workflows.serve/2` or `mix condukt.workflows.serve`.
- `mix condukt.workflows.check` is the validation gate for workflow graphs,
  tool refs, sandbox kinds, and model identifiers.

## Workflow

- After every change, create a git commit and push it to the current branch.

## Elixir

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

## Marketing site (`website/`)

The marketing site lives under `website/` and is built with [Eleventy](https://www.11ty.dev/).

- Source: `website/src/` (templates use Nunjucks, layouts in `website/src/_includes/layouts/`).
- Package manager: [aube](https://github.com/endevco/aube), pinned in `mise.toml`. Use `aube ci`, `aube install`, `aube add <pkg>`, `aube run <script>` (or `aubr <script>`). Do not invoke `npm`/`pnpm`/`yarn` directly.
- Build: `cd website && aube ci && aube run build` — outputs to `website/_site`.
- Local preview: `cd website && aube run dev`.
- Deployment: pushes to `main` that touch `website/**` deploy to the Cloudflare Pages project `condukt-website` via `.github/workflows/website.yml`. The job uses `cloudflare/wrangler-action` (`wrangler pages deploy`) and reads `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from repo secrets. The custom domain `condukt.tuist.dev` is bound to that Pages project in the Cloudflare dashboard.
- Pages config: `website/wrangler.toml` declares the project name and `pages_build_output_dir`.
- Toolchain: Node and aube are pinned in `mise.toml`; bump there rather than ad-hoc.

## Documentation (`guides/`)

Per-feature ExDoc pages live under `guides/` and are wired into `mix.exs` via `extras` and `groups_for_extras`. They are published to HexDocs alongside the API reference.

- When adding, removing, or meaningfully changing a feature (tools, sessions, compaction, redaction, providers, telemetry, project instructions, streaming, etc.), update the corresponding page under `guides/` in the same change.
- When introducing a new top-level feature, add a new guide page and register it in both `extras` and `groups_for_extras` in `mix.exs`.
- Avoid em dashes in guide prose (use colons, commas, or periods).
- Verify with `mix docs` before committing.

## Keeping this file up to date

- Whenever a change adds, removes, or meaningfully alters an agent capability, workflow, deployment target, or required tool, update this file in the same change. The agent reads `AGENTS.md` at startup and stale entries cause it to act on outdated assumptions.
