# Unification plan: Plasma + Condukt into one repo, one brand

This is the working plan for the merge. The strategy notes in
`~/Downloads/plasma.md` explain the *why*; this document covered the *what*
and the *in what order* while the merge was in flight, and now records the
decisions that shaped the result.

Status: **executed**. All six phases below landed on `feat/condukt-merge`.

---

## Target shape

One repository (`github.com/tuist/condukt`), one brand ("Condukt"), one
versioned release line that ships both the Hex library and the Rust CLI binary
plus the Phoenix web app. Two source languages (Elixir and Rust), three
product surfaces (library, CLI, web), one wire protocol in the middle.

```
condukt/
├── lib/                          # Elixir library (unchanged)
├── test/                         # Elixir tests (unchanged)
├── native/                       # Existing NIFs (unchanged)
│   ├── condukt_bashkit/
│   ├── condukt_egress/
│   └── condukt_microsandbox/
├── cli/                          # NEW: Rust workspace for the terminal app
│   ├── Cargo.toml                # renamed from root Cargo.toml
│   ├── Cargo.lock
│   └── crates/
│       ├── condukt/              # renamed from plasma/  (binary)
│       ├── condukt-inference/    # renamed from plasma-inference/
│       ├── condukt-protocol/     # renamed from plasma-protocol/
│       ├── condukt-session/      # renamed from plasma-session/
│       ├── condukt-tools/        # renamed from plasma-tools/
│       └── condukt-wasm/         # renamed from plasma-wasm/ (powers the browser path)
├── web/                          # NEW: Phoenix app (moved from plasma/web)
│   ├── lib/                      # namespace PlasmaSite -> ConduktSite
│   ├── assets/
│   ├── config/
│   ├── priv/docs/{guide,reference}/   # docs that travel with the app
│   └── ...
├── packages/condukt/             # NEW: @tuist/condukt (was @tuist/plasma, WASM-backed)
├── website/                      # KEEP for now, re-evaluate at end of phase 4
├── docs/                         # repo-level docs (unchanged)
├── .github/workflows/            # new: condukt-cli.yml, condukt-web.yml; updated release.yml
├── mise.toml                     # new tools: aube stays; rust stays; elixir stays
├── AGENTS.md                     # rewritten to describe all three surfaces
├── README.md                     # rewritten to introduce all three surfaces
└── CHANGELOG.md                  # kept; this merge is a major version bump
```

The two-NIF Rust code in `native/condukt_bashkit/` and
`native/condukt_microsandbox/` stays where it is — they are tightly coupled to
the Elixir library and follow a different build path. The CLI workspace in
`cli/` is a separate Rust workspace with its own `Cargo.lock`, so the library's
NIF build and the CLI's release build don't fight each other.

---

## Brand rename table

| Before                       | After                       |
|------------------------------|-----------------------------|
| `plasma` (binary)            | `condukt`                   |
| `plasma-protocol` (crate)    | `condukt-protocol`          |
| `plasma-inference` (crate)   | `condukt-inference`         |
| `plasma-openrouter` (crate)  | **dropped** (see open Q 2)  |
| `plasma-session` (crate)     | `condukt-session`           |
| `plasma-tools` (crate)       | `condukt-tools`             |
| `plasma-wasm` (crate)        | `condukt-wasm`              |
| `@tuist/plasma` (npm)        | `@tuist/condukt`            |
| `plasma_site` (Elixir app)   | `condukt_site`              |
| `PlasmaSite.*` (modules)     | `ConduktSite.*`             |
| `plasma.tuist.dev` (domain)  | `condukt.tuist.dev` (no change) |
| `PLASMA_*` env vars          | `CONDUKT_*`                 |
| `~/.config/plasma`           | `~/.config/condukt`         |
| `mise use -g github:tuist/plasma`  | `mise use -g github:tuist/condukt` |
| `ghcr.io/tuist/plasma-site`  | `ghcr.io/tuist/condukt-site`|

---

## Phases

Each phase ends with a green test run and a single commit on the work branch.
The work branch is `feat/condukt-merge`; PRs into `main` should be small enough
to read in one sitting.

### Phase 0 — Pre-flight (small)

- Document the plan in `UNIFICATION_PLAN.md` (this file) and link it from
  `AGENTS.md` so future agents know the destination.
- Decide layout (this file) and the rename table.
- Stand up a scratch `sc worktree` if the user wants isolation; the current
  worktree is `sc-quantum-boson-d61a` on `feat/condukt-merge`.

### Phase 1 — Rust CLI workspace under `cli/`

- Copy `plasma/{Cargo.toml,Cargo.lock,crates/,rust-toolchain.toml}` into
  `cli/`. Leave the file contents alone; this is a pure move.
- Update the workspace `Cargo.toml` paths (`crates/plasma-...` →
  `cli/crates/condukt-...`).
- Rename crate directories and their `Cargo.toml` `name` fields per the table.
- Update the binary's `main.rs` to read `argv[0]`-based naming if it does not
  already.
- Update `mise.toml` to add the `cli` workspace.
- Add `.github/workflows/condukt-cli.yml` mirroring plasma's `ci.yml`
  (build, test, clippy, fmt) and a `cli-release.yml` that produces the
  `condukt-<ver>-<target>.tar.gz` artifacts (was `plasma-*` in plasma's
  release.yml).
- Verify: `cd cli && cargo build --all-targets` passes; `cargo test` passes;
  `cargo clippy --all-targets --all-features -- --deny warnings` passes.

This phase is mechanical but ~6,000 lines of renames. The point is to land the
move first, with no behavior changes, and let CI prove it still works.

### Phase 2 — Brand rename inside the CLI

- Rewrite all user-facing strings: clap command name, the `usage` text,
  shell-completion names, env vars (`PLASMA_OPENROUTER_API_KEY` →
  `CONDUKT_OPENROUTER_API_KEY`), credential dir, the OAuth redirect path,
  the `~/.config/plasma` XDG default, the installer URL.
- Update the in-binary strings: `--help`, error messages, footer status,
  footer session name, the prompt that says `plasma>` or similar.
- Update integration tests that touch the binary name.
- Update `crates/condukt-openrouter/` → see open Q 2 about whether this
  provider leaves the CLI now or stays for the duration of the merge.

This phase is also mechanical, but every string change needs a test that
asserts on it, so a stray `plasma` is caught.

### Phase 3 — Move the Phoenix web app to `web/`

- Copy `plasma/web/` into `web/`.
- Rename the Elixir app and modules: `plasma_site` → `condukt_site`,
  `PlasmaSite.*` → `ConduktSite.*`, config keys, env var names.
- Port the worktree-instance suffix scheme to the new name
  (`plasma_site_dev_SUFFIX` → `condukt_site_dev_SUFFIX`, `PLASMA_SITE_DEV_INSTANCE`
  → `CONDUKT_SITE_DEV_INSTANCE`).
- Update the `mix.exs` alias for `wasm.build` to point at the relocated
  `cli/` workspace.
- Add `condukt` as a dep of the web app (or document why it isn't) and wire
  `Condukt.Plug` if the web app needs to expose agents — see open Q 3.
- Add `.github/workflows/condukt-web.yml` mirroring plasma's `web.yml` Docker
  publish path, renaming the image to `ghcr.io/tuist/condukt-site`.
- Update `web/Dockerfile` to also build the `cli/` workspace if the image is
  going to ship the CLI binary.
- Update `web/README.md` to reflect the new names and the new repo location.

### Phase 4 — Reconcile the existing content and docs

This is the phase that needs the most care. Three sources of content have to
land on the same site, all under the Plasma / Noora visual language.

**Marketing copy.** The Phoenix `home.html.heex` is the new home; the
Eleventy `website/src/index.njk` is the existing home. The Phoenix version is
the one that ships, but its copy needs to be rewritten so it covers both
surfaces:

- the Elixir library (one-shot, persistent, MCP, sandboxes, network policy,
  redaction, compaction, plug routes, telemetry);
- the Rust CLI (TUI, `exec`, `acp`, OpenRouter auth, import-pi-credentials,
  WebAssembly, slash commands);
- the web app (browser agent, OAuth, embedded docs).

Condukt's existing `index.njk` features section is a useful source for the
library copy. The plasma `home.html.heex` is the visual base.

**The `guides/` directory.** The plan assumed the ExDoc guides would stay in
`guides/` next to a separate site tree. The reconciliation pass went further:
`guides/` is gone, and every page now lives once under `web/priv/docs/`. The
site serves the whole tree, and `mix.exs` points its ExDoc `extras` at
`web/priv/docs/framework/elixir/*.md`, so HexDocs and the site render the same
files. The site tree is organized by journey (`cli/`, `framework/elixir/`,
`framework/rust/`) rather than by genre (`guide/`, `reference/`).

**Blog.** Condukt's blog at `website/src/blog/posts/` (Eleventy) has 4 posts
that predate the CLI. The Phoenix site has no blog. Two options:

- (a) Keep the Eleventy blog and the Phoenix docs as separate surfaces.
- (b) Drop the Eleventy site entirely and add a blog route to the Phoenix
  app (e.g. `/blog/<slug>`) with the same posts ported to EEx.

Option (a) is a smaller change. Option (b) is consistent with the user's
stated goal of "respecting the design of the Plasma marketing pages and docs"
unambiguously. See open Q 4.

### Phase 5 — CI, release, and repo metadata

- `cliff.toml` and `cliff-release.toml`: confirm the conventional-commits
  parser is happy with the unified history once the merge commit lands.
- `release.yml`: now produces a Hex release, a multi-target CLI release, and
  a web Docker publish. Two detect jobs, two build matrixes, two publish
  steps. Reuse the existing one and add a second matrix.
- `condukt.yml` (existing) keeps the Elixir CI surface.
- `condukt-egress.yml` (existing) is unaffected.
- `website.yml` (existing): see open Q 4 (drop it if we drop the Eleventy
  site).
- `README.md`, `AGENTS.md`, `LICENSE`/`MIT.md`, top-level `mise.toml`,
  `.gitignore`, `.credo.exs`, `.formatter.exs`: rewrite the parts that talk
  about the repo's surface area.

### Phase 6 — The brand cutover

This is the moment the old `tuist/plasma` repo becomes a read-only redirect.
Not code, but worth sequencing:

- Push a final `tuist/plasma` release that says "moved to
  github.com/tuist/condukt".
- Add a GitHub repo redirect from `tuist/plasma` to `tuist/condukt` if
  GitHub still supports that path; otherwise a `README.md` redirect.
- Announce on the Condukt blog (when it lands in phase 4) and the
  `#condukt` channel.

---

## Open questions for the user

1. **Directory layout.** Is `cli/` the right home for the Rust workspace, or
   do you prefer `rust/`, `app/cli/`, or some other name? I'm defaulting to
   `cli/` because it matches the strategy-doc framing ("the CLI is in Rust")
   and is short.

2. **OpenRouter provider.** Plasma's `plasma-openrouter` crate is the only
   inference provider in the CLI. The strategy doc says "the OpenRouter
   provider will leave the CLI". I read that as: pull OpenRouter out of the
   Rust CLI in this PR, on the theory that the Rust CLI is going to grow a
   multi-provider layer soon anyway and a single-provider crate is the
   worst of both worlds. The alternative is to keep the OpenRouter provider
   inside the CLI for now and remove it in a follow-up. Which?

3. **Web app ↔ library wiring.** The Phoenix web app today does not depend
   on `condukt`. Plasma is a separate product. After the merge, is the web
   app just the marketing + docs + browser-agent surface, or is it also
   where a hosted Condukt service lives (calling `Condukt.run/3`,
   `Condukt.Plug`, etc.)? Today it does the former. I want to confirm
   before I add a dep on `condukt` in `web/mix.exs`.

4. **Eleventy site.** The strategy doc doesn't address the existing
   Eleventy site. Three options, listed in order of how invasive they are:
   - (a) **Keep** the Eleventy site as-is for now. The Phoenix site is the
     new marketing + docs surface; the Eleventy site stays a static
     shadow. The blog lives on the Eleventy site.
   - (b) **Port** the Eleventy content (home, blog) into the Phoenix site
     one-for-one, and delete `website/`. The blog becomes a Phoenix route.
   - (c) **Hybrid.** Phoenix handles marketing and docs; the Eleventy site
     remains a thin static blog only.
   I am leaning (b) because you said "respecting the design of the Plasma
   marketing pages and docs" and the Eleventy site has the older visual
   language, but it is the most invasive and the slowest.

5. **WASM / browser package.** Do we want `@tuist/condukt` (the
   `plasma-wasm` crate + the `packages/plasma/` npm wrapper) in this merge?
   The browser agent in the Phoenix site depends on it. I'd say yes — it
   is part of the same product surface — but it's another ~500 lines and
   its own release pipeline, so calling it out.

6. **Scope of this PR / turn.** I can do all of phase 1 + 2 in a single
   sitting, or all of phases 1-3, or stop after phase 4. Where do you
   want the first stopping point?

---

## What this plan does *not* cover

- The `SessionDriver` trait and the `RemoteSession` HTTP/WS bridge from the
  strategy doc. Those are real work, but they belong in a follow-up. The
  CLI lands as a local-only Rust loop first; the remote driver is its own
  PR that depends on `Condukt.Plug` being stable.
- The "two surfaces, one wire protocol" plan in detail. The CLI keeps its
  current `Message` and `ToolDefinition` shapes from `plasma-protocol`; we
  do not invent a new wire protocol in this PR.
- The `tuist/plasma` GitHub repo redirect. That is phase 6, not code.
