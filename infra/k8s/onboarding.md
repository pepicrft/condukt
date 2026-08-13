# Condukt site cluster onboarding

This runbook covers the one-time cluster setup behind https://condukt.tuist.dev.
Day-to-day deploys are automatic: `.github/workflows/condukt-web.yml` builds the
image on every push to `main` that touches the site, then runs
`helm upgrade --install` and a smoke test.

The site is deployed into an existing workload cluster rather than one of its
own. Everything below is namespaced to `condukt-production` except the DNS
controller, which is cluster scoped.

## Prerequisites

The target cluster must already run:

- `ingress-nginx` with a LoadBalancer address;
- `cert-manager` with a `letsencrypt-prod` ClusterIssuer;
- `external-secrets-operator` with a 1Password `ClusterSecretStore` named
  `onepassword` that can read the `condukt-k8s-production` vault;
- `cloudnative-pg`, only if `postgres.enabled` is ever turned on.

## 1Password items

Create these in the `condukt-k8s-production` vault:

| Item | Field | Contents |
| --- | --- | --- |
| `condukt-secret-key-base` | `password` | Output of `mix phx.gen.secret` |
| `condukt-ghcr-pull` | `notesPlain` | A `.dockerconfigjson` document for a `read:packages` token |
| `kubeconfig: condukt-production` | document | Kubeconfig for the deployer ServiceAccount |

The chart reads the first two through the `onepassword` ClusterSecretStore; the
GitHub Actions job reads the third with the 1Password CLI.

## Namespace and deploy credentials

```bash
kubectl apply -f infra/k8s/ci-service-account.yaml

kubectl -n condukt-production get secret github-actions-deployer-token \
  -o jsonpath='{.data.token}' | base64 -d
```

Build a kubeconfig for that ServiceAccount, pointing at the same API server and
CA as the cluster-admin kubeconfig, and upload it to 1Password as the document
named in the table above. `OP_SERVICE_ACCOUNT_TOKEN` in the repository secrets
must be able to read it.

## DNS controller

external-dns watches the site Ingress and keeps the `condukt.tuist.dev`
Cloudflare record pointing at the ingress-nginx LoadBalancer.

Prerequisites:

- The current `KUBECONFIG` points at the target cluster.
- A Cloudflare API token with `Zone:Read` and `DNS:Edit` on the `tuist.dev`
  zone is stored at
  `op://condukt-k8s-production/cloudflare-tuist-dns/credential`.

If the cluster already runs an external-dns release for another domain, install
this one alongside it under its own release name so the two keep separate txt
ownership. Never point two controllers at the same records.

```bash
tmpdir="$(mktemp -d)"
chmod 700 "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
token_file="$tmpdir/cloudflare-api-token"
op read 'op://condukt-k8s-production/cloudflare-tuist-dns/credential' | tr -d '\n' >"$token_file"
chmod 600 "$token_file"

kubectl create namespace external-dns --dry-run=client -o yaml | kubectl apply -f -
kubectl -n external-dns create secret generic cloudflare-api-token \
  --from-file=token="$token_file" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add external-dns https://kubernetes-sigs.github.io/external-dns 2>/dev/null \
  || helm repo update external-dns
helm upgrade --install external-dns-condukt external-dns/external-dns \
  --version 1.21.1 \
  -n external-dns --create-namespace \
  -f infra/k8s/external-dns-values.yaml \
  --timeout 5m --wait
```

Validate:

```bash
kubectl -n external-dns get deploy external-dns-condukt
kubectl -n external-dns logs deploy/external-dns-condukt | tail -20
dig @1.1.1.1 condukt.tuist.dev A +short
```

The record is proxied or not depending on the Cloudflare zone default. If the
certificate fails to issue, check that the record is grey-clouded long enough
for the HTTP-01 challenge, or switch the issuer to DNS-01.

## First release

The workflow performs the release, but it can be run by hand against the same
chart:

```bash
helm upgrade --install condukt-site infra/helm/condukt-site \
  --namespace condukt-production --create-namespace \
  --set image.tag="sha-$(git rev-parse --short=12 HEAD)" \
  --rollback-on-failure --timeout 15m --wait

kubectl -n condukt-production rollout status deploy/condukt-site
curl -fsS https://condukt.tuist.dev/ready
```

## Notes

- The site runs without a database. `postgres.enabled` is `false`, and the app
  starts its Repo only when `DATABASE_URL` is present. Enabling the value
  provisions a CloudNativePG cluster and wires the URL into the pod.
- `SECRET_KEY_BASE` is the only required application secret. OpenRouter sign-in
  uses PKCE and holds the resulting key in the visitor's session, so no
  provider credential lives in the cluster.
