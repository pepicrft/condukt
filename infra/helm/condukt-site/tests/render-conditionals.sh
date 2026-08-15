#!/usr/bin/env bash
set -euo pipefail

chart_path="${CHART_PATH:-infra/helm/condukt-site}"
rendered_manifest="${RENDERED_MANIFEST:-}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

render() {
  "${HELM:-helm}" template condukt-site "$chart_path" --namespace condukt-production "$@"
}

resource_count() {
  grep -c "^kind: $2\$" "$1" || true
}

expect_resource_count() {
  local file="$1"
  local kind="$2"
  local expected="$3"
  local actual
  actual="$(resource_count "$file" "$kind")"
  if [[ "$actual" != "$expected" ]]; then
    echo "expected $expected $kind resources in $file, found $actual" >&2
    exit 1
  fi
}

if [[ -n "$rendered_manifest" ]]; then
  if [[ ! -f "$rendered_manifest" ]]; then
    echo "rendered manifest not found: $rendered_manifest" >&2
    exit 1
  fi
  cp "$rendered_manifest" "$tmpdir/default.yaml"
else
  render >"$tmpdir/default.yaml"
fi
grep -q 'host: condukt.dev' "$tmpdir/default.yaml"
grep -q 'path: /ready' "$tmpdir/default.yaml"

# condukt.dev is served through a namespaced Issuer, because the cluster's
# ClusterIssuer only holds a token for the tuist.dev zone. The cluster-issuer
# annotation must not appear alongside it: cert-manager would have two
# conflicting instructions.
grep -q 'cert-manager.io/issuer: "letsencrypt-condukt"' "$tmpdir/default.yaml"
if grep -q 'cert-manager.io/cluster-issuer' "$tmpdir/default.yaml"; then
  echo "both issuer and cluster-issuer annotations rendered" >&2
  exit 1
fi
expect_resource_count "$tmpdir/default.yaml" Issuer 1

# No external-dns manages this zone, so nothing should ask it to proxy.
if grep -q 'external-dns.alpha.kubernetes.io/cloudflare-proxied' "$tmpdir/default.yaml"; then
  echo "cloudflare-proxied rendered for a zone external-dns does not manage" >&2
  exit 1
fi

# Clearing the namespaced issuer falls back to the cluster-wide one, for a
# cluster whose ClusterIssuer does cover the zone.
render --set-string ingress.issuer= >"$tmpdir/cluster-issuer.yaml"
grep -q 'cert-manager.io/cluster-issuer: "letsencrypt-cloudflare"' "$tmpdir/cluster-issuer.yaml"

# The package is public, so nothing should ask the kubelet for credentials
# unless a pull secret is configured on purpose.
if grep -q '^[[:space:]]*imagePullSecrets:' "$tmpdir/default.yaml"; then
  echo "imagePullSecrets rendered while image.pullSecretName was empty" >&2
  exit 1
fi

render --set-string image.pullSecretName=ghcr-pull >"$tmpdir/image-pull-secret.yaml"
grep -q '^[[:space:]]*imagePullSecrets:' "$tmpdir/image-pull-secret.yaml"

render --set externalSecrets.enabled=true --set externalSecrets.pullSecret.enabled=true --set-string image.pullSecretName=ghcr-pull >"$tmpdir/external-secrets-enabled-pull-secret-enabled.yaml"
# app secret + GHCR pull secret + the Cloudflare token for the DNS-01 issuer
expect_resource_count "$tmpdir/external-secrets-enabled-pull-secret-enabled.yaml" ExternalSecret 3

render --set externalSecrets.enabled=true --set externalSecrets.pullSecret.enabled=false >"$tmpdir/external-secrets-enabled-pull-secret-disabled.yaml"
expect_resource_count "$tmpdir/external-secrets-enabled-pull-secret-disabled.yaml" ExternalSecret 2

render --set externalSecrets.enabled=false --set externalSecrets.pullSecret.enabled=false >"$tmpdir/external-secrets-disabled.yaml"
expect_resource_count "$tmpdir/external-secrets-disabled.yaml" ExternalSecret 0

render \
  --set externalSecrets.enabled=true \
  --set externalSecrets.pullSecret.enabled=true \
  --set-string image.pullSecretName= \
  >"$tmpdir/external-secrets-enabled-pull-secret-enabled-no-name.yaml"
expect_resource_count "$tmpdir/external-secrets-enabled-pull-secret-enabled-no-name.yaml" ExternalSecret 2

# The site runs without a database. Postgres stays off unless it is asked for,
# and turning it on must both provision the cluster and wire DATABASE_URL.
expect_resource_count "$tmpdir/default.yaml" Cluster 0
if grep -q 'DATABASE_URL' "$tmpdir/default.yaml"; then
  echo "DATABASE_URL wired into the pod while postgres was disabled" >&2
  exit 1
fi

render --set postgres.enabled=true >"$tmpdir/postgres-enabled.yaml"
expect_resource_count "$tmpdir/postgres-enabled.yaml" Cluster 1
grep -q 'DATABASE_URL' "$tmpdir/postgres-enabled.yaml"
