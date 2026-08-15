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
grep -q 'host: condukt.tuist.dev' "$tmpdir/default.yaml"
grep -q 'path: /ready' "$tmpdir/default.yaml"
grep -q 'cert-manager.io/cluster-issuer: "letsencrypt-cloudflare"' "$tmpdir/default.yaml"
grep -q 'external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"' "$tmpdir/default.yaml"

# The package is public, so nothing should ask the kubelet for credentials
# unless a pull secret is configured on purpose.
if grep -q '^[[:space:]]*imagePullSecrets:' "$tmpdir/default.yaml"; then
  echo "imagePullSecrets rendered while image.pullSecretName was empty" >&2
  exit 1
fi

render --set-string image.pullSecretName=ghcr-pull >"$tmpdir/image-pull-secret.yaml"
grep -q '^[[:space:]]*imagePullSecrets:' "$tmpdir/image-pull-secret.yaml"

render --set externalSecrets.enabled=true --set externalSecrets.pullSecret.enabled=true --set-string image.pullSecretName=ghcr-pull >"$tmpdir/external-secrets-enabled-pull-secret-enabled.yaml"
expect_resource_count "$tmpdir/external-secrets-enabled-pull-secret-enabled.yaml" ExternalSecret 2

render --set externalSecrets.enabled=true --set externalSecrets.pullSecret.enabled=false >"$tmpdir/external-secrets-enabled-pull-secret-disabled.yaml"
expect_resource_count "$tmpdir/external-secrets-enabled-pull-secret-disabled.yaml" ExternalSecret 1

render --set externalSecrets.enabled=false --set externalSecrets.pullSecret.enabled=false >"$tmpdir/external-secrets-disabled.yaml"
expect_resource_count "$tmpdir/external-secrets-disabled.yaml" ExternalSecret 0

render \
  --set externalSecrets.enabled=true \
  --set externalSecrets.pullSecret.enabled=true \
  --set-string image.pullSecretName= \
  >"$tmpdir/external-secrets-enabled-pull-secret-enabled-no-name.yaml"
expect_resource_count "$tmpdir/external-secrets-enabled-pull-secret-enabled-no-name.yaml" ExternalSecret 1

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
