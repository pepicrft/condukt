# syntax=docker/dockerfile:1.7
#
# The build context is the repository root, because the site depends on the
# Condukt library at the root as a path dependency: the terminal on the home
# page runs a real session rather than a copy of the loop.

FROM docker.io/library/elixir:1.19.5-otp-28-slim AS web-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

ENV ERL_FLAGS="+JPperf true" \
    MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force
WORKDIR /src/web

# The library, as the path dependency resolves it. Its two Rust crates are
# disabled from web/mix.exs, so no Rust toolchain is needed here; see the
# comment there for why the site never starts those sandboxes.
COPY mix.exs mix.lock /src/
COPY lib /src/lib
COPY native /src/native

COPY web/mix.exs web/mix.lock ./
COPY web/config ./config
RUN mix deps.get --only prod && mix deps.compile

COPY web/assets ./assets
COPY web/lib ./lib
COPY web/priv ./priv
COPY web/rel ./rel

RUN chmod 755 rel/overlays/bin/migrate rel/overlays/bin/server

RUN rm -rf priv/static/assets priv/static/cache_manifest.json

RUN mix compile \
    && mix esbuild.install --if-missing \
    && mix esbuild condukt_site --minify \
    && mix phx.digest \
    && mix release

FROM docker.io/library/debian:trixie-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libncurses6 libstdc++6 openssl \
    && rm -rf /var/lib/apt/lists/*

ENV HOME=/app \
    LANG=C.UTF-8 \
    PHX_SERVER=true \
    PORT=4000

WORKDIR /app
COPY --from=web-builder --chown=nobody:nogroup /src/web/_build/prod/rel/condukt_site ./

USER nobody
EXPOSE 4000

CMD ["/app/bin/server"]
