# AGENTS.md

## Command Execution

- For running bash commands from Elixir, use `MuonTrap` instead of `System`.
- Prefer `MuonTrap` because it propagates process shutdowns to child processes.
- Reference: https://hexdocs.pm/muontrap/readme.html

## Workflow

- After every change, create a git commit and push it to the current branch.

## Elixir

- Do not type Elixir code by hand when avoidable. Prefer structural edits and tool-assisted changes.

## Marketing site (`website/`)

The marketing site lives under `website/` and is built with [Eleventy](https://www.11ty.dev/).

- Source: `website/src/` (templates use Nunjucks, layouts in `website/src/_includes/layouts/`).
- Build: `cd website && npm ci && npm run build` — outputs to `website/_site`.
- Local preview: `cd website && npm run dev`.
- Deployment: pushes to `main` that touch `website/**` deploy to Cloudflare Workers via `.github/workflows/website.yml`. The job uses `cloudflare/wrangler-action` and reads `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from repo secrets.
- Worker config: `website/wrangler.toml` (static-assets only — no server code).
- Toolchain: Node is pinned in `mise.toml`; bump there rather than ad-hoc.

## Keeping this file up to date

- Whenever a change adds, removes, or meaningfully alters an agent capability, workflow, deployment target, or required tool, update this file in the same change. The agent reads `AGENTS.md` at startup and stale entries cause it to act on outdated assumptions.
