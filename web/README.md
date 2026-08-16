# Condukt site

This [Phoenix](https://www.phoenixframework.org/) application owns Condukt's marketing pages, its documentation, OpenRouter authorization, and the agent behind the terminal on the home page.

## Development

Run PostgreSQL locally, then:

```sh
mix setup
mix phx.server
```

`mix setup` creates the database and builds the site assets. Open the address printed by the server and select **Log in with OpenRouter**. OpenRouter returns to the same worktree-specific address and the agent input becomes available.

Each Git worktree receives a stable suffix from 100 through 999. Development uses port `4000 + suffix` and database `condukt_site_dev_SUFFIX`. Tests use port `4002 + suffix` and a separate `condukt_site_test_SUFFIX` database. Set `CONDUKT_SITE_DEV_INSTANCE` to an unused suffix when an explicit value is useful.

## Where the terminal runs

The site depends on the Condukt library at the repository root, so the terminal on the home page
is a real `Condukt.Session`: `ConduktSiteWeb.TerminalLive` starts one per visitor and streams the
turn as it happens.

The tools go the other way. The page declares what it can do when the socket opens, and
`ConduktSite.BrowserTools` turns each declaration into a tool whose call travels back down the
socket for the browser to run. The two it declares list directories and read bounded text files
from the public `tuist/condukt` repository, in `assets/js/repository_tools.mjs`.

That split is deliberate on both counts. GitHub rate-limits unauthenticated requests per address,
so reading from the visitor's browser keeps each visitor on their own allowance rather than a
shared server one. And the agent runs on a server it must not be able to reach, so its entire
reach being the page's to grant is a stronger guarantee than auditing a list of server-side tools.

The OpenRouter credential stays in a signed, encrypted session cookie that page JavaScript cannot
read. The LiveView reads it at mount and hands it to the session, so inference is billed to the
visitor without the key ever reaching the page.

Interactive controls come from the web-component build of
[`@tuist/noora`](https://www.npmjs.com/package/@tuist/noora), pinned to version `0.86.0`
on jsDelivr with subresource integrity hashes.

## Production image

Condukt is packaged as a conventional Phoenix release. Pull requests build the production image,
and a merge to `main` publishes it to `ghcr.io/tuist/condukt` with immutable commit and
`latest` tags. The repository deliberately does not add a proxy Worker or couple the application
to a hosting provider.

The runtime must supply `PHX_HOST` and `SECRET_KEY_BASE`, generated with `mix phx.gen.secret`.

The site does not currently persist application data, so a database is optional. When
`DATABASE_URL` is supplied to the container in the future, the release starts the repository and
runs migrations before booting the server.

To build the same image locally with Docker running:

```sh
docker build --platform linux/amd64 -t condukt-site .
```
