# Condukt site

This [Phoenix](https://www.phoenixframework.org/) application owns Condukt's marketing pages, OpenRouter authorization, and browser inference proxy.

## Development

Run PostgreSQL locally, then:

```sh
mix setup
mix phx.server
```

`mix setup` creates the database, compiles the browser package to [WebAssembly](https://webassembly.org/), and builds the site assets. Open the address printed by the server and select **Log in with OpenRouter**. OpenRouter returns to the same worktree-specific address and the agent input becomes available.

Each Git worktree receives a stable suffix from 100 through 999. Development uses port `4000 + suffix` and database `condukt_site_dev_SUFFIX`. Tests use port `4002 + suffix` and a separate `condukt_site_test_SUFFIX` database. Set `CONDUKT_SITE_DEV_INSTANCE` to an unused suffix when an explicit value is useful.

## Browser boundary

The page imports `@tuist/condukt` from its own static files. It supplies:

- inference through the same-origin `/api/completions` endpoint and a configured model;
- two explicit tools that list directories and read bounded text files from the public
  `tuist/condukt` GitHub repository.

The OpenRouter credential remains in a signed, encrypted session cookie that page JavaScript cannot read. It is read only by the Elixir completion endpoint and is never included in page markup or JavaScript.

The browser agent is a [Lit](https://lit.dev/) custom element imported from a pinned jsDelivr
module. Its interactive controls come from the web-component build of
[`@tuist/noora`](https://www.npmjs.com/package/@tuist/noora), also pinned to version `0.86.0`
on jsDelivr with subresource integrity hashes.

## Production image

Condukt is packaged as a conventional Phoenix release. Pull requests build the production image,
and a merge to `main` publishes it to `ghcr.io/tuist/condukt-site` with immutable commit and
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
