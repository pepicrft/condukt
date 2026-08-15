# Condukt site cluster onboarding

This runbook covers the one-time setup behind https://condukt.dev.
Day-to-day deploys are automatic: `.github/workflows/condukt-web.yml` builds the
image on every push to `main` that touches the site, then runs
`helm upgrade --install` and a smoke test.

The site is a tenant of the shared `tuist-k8s-production` cluster, in its own
`condukt-production` namespace, the same arrangement Once uses with
`once-production`.

## What the cluster already provides

Confirmed against `tuist-k8s-production`, so none of it needs installing:

- `ingress-nginx` with the LoadBalancer at `91.98.14.217`, serving `tuist.dev`
  and `registry.tuist.dev`.
- `cert-manager`. Its `letsencrypt-cloudflare` ClusterIssuer holds a Cloudflare
  token for the `tuist.dev` zone only, so it cannot solve DNS-01 for
  `condukt.dev`. The chart ships its own namespaced `Issuer`
  (`letsencrypt-condukt`) with a token scoped to the `condukt.dev` zone, the
  same way Once does for `buildonce.dev`.
- `platform-external-dns` in the `platform` namespace, watching ingresses
  cluster-wide with `--domain-filter=tuist.dev --policy=sync
  --txt-owner-id=tuist-platform`. **It does not manage `condukt.dev`**, so
  creating the Ingress does not create the DNS record: that is a manual step
  below. Do not widen the domain filter or install a second external-dns for
  `tuist.dev`; the running one uses `sync` policy and owns that zone.
- `external-secrets` with the `onepassword` ClusterSecretStore, pinned to the
  `tuist-k8s-production` 1Password vault.

## 1Password

The ClusterSecretStore resolves items in the `tuist-k8s-production` vault only.
Items for the chart go there:

| Vault | Item | Field | Contents |
| --- | --- | --- | --- |
| `tuist-k8s-production` | `condukt-secret-key-base` | `password` | Output of `mix phx.gen.secret` |
| `tuist-k8s-production` | `cloudflare-condukt-dns` | `credential` | Cloudflare API token with `Zone.DNS:Edit` on `condukt.dev`, used by cert-manager for DNS-01 |
| `condukt-k8s-production` | `kubeconfig: condukt-production` | document | Kubeconfig for the deployer ServiceAccount |

The kubeconfig is read by the 1Password CLI inside GitHub Actions, not by the
cluster, so it can live in Condukt's own vault. The repository's
`OP_SERVICE_ACCOUNT_TOKEN` must be able to read that vault.

If you would rather keep the application secret in `condukt-k8s-production`
too, that needs a second ClusterSecretStore pinned to it and the 1Password
service account granted access; then set `externalSecrets.storeRef.name` in
`values.yaml`. One store and one vault is the simpler path and matches Once.

## Namespace and deploy credentials

```bash
kubectl --context tuist-k8s-production apply -f infra/k8s/ci-service-account.yaml

kubectl --context tuist-k8s-production -n condukt-production \
  get secret github-actions-deployer-token -o jsonpath='{.data.token}' | base64 -d
```

Build a kubeconfig for that ServiceAccount, pointing at the same API server and
CA as the admin kubeconfig, and upload it to 1Password as the document above.

## Container image

`ghcr.io/tuist/condukt` must be public, like `ghcr.io/tuist/once-web`, so
the kubelet pulls it anonymously. Check the package visibility after the first
push to `main`. If it has to stay private, create a `condukt-ghcr-pull` item in
`tuist-k8s-production` holding a `.dockerconfigjson` document, then set
`image.pullSecretName=ghcr-pull` and `externalSecrets.pullSecret.enabled=true`.

## DNS

`condukt.dev` is a Cloudflare zone of its own, and nothing in the cluster
reconciles it. Create the record by hand, pointing at the shared ingress
LoadBalancer, and leave it **DNS only** (grey cloud), matching `buildonce.dev`:

| Type | Name | Content | Proxy |
| --- | --- | --- | --- |
| A | `condukt.dev` | `91.98.14.217` | DNS only |

Proxying would work for HTTP but is pointless here: the certificate is issued
through DNS-01 by the in-cluster issuer, and nothing else on this zone benefits
from Cloudflare's edge. If it is ever turned on, the origin still has to answer
the ingress host header.

## First release

The workflow performs the release, but the same chart can be applied by hand.
Note there is no `--create-namespace`: the namespace comes from the bootstrap
manifest above, and Helm 4 would server-side apply the Namespace object, which
the namespace-scoped deployer cannot patch.

```bash
helm --kube-context tuist-k8s-production upgrade --install condukt-site \
  infra/helm/condukt-site \
  --namespace condukt-production \
  --set image.tag="sha-$(git rev-parse HEAD)" \
  --rollback-on-failure --timeout 15m --wait

kubectl --context tuist-k8s-production -n condukt-production rollout status deploy/condukt-site
```

Then watch TLS settle. The certificate cannot issue until
`cloudflare-condukt-dns` exists in 1Password and ESO has synced it into the
namespace:

```bash
kubectl --context tuist-k8s-production -n condukt-production get externalsecret
kubectl --context tuist-k8s-production -n condukt-production get issuer letsencrypt-condukt
kubectl --context tuist-k8s-production -n condukt-production get certificate
dig @1.1.1.1 condukt.dev +short
curl -fsS https://condukt.dev/ready
```

## Notes

- The site runs without a database. `postgres.enabled` is `false`, and the app
  starts its Repo only when `DATABASE_URL` is present. Enabling the value
  provisions a CloudNativePG cluster and wires the URL into the pod.
- `SECRET_KEY_BASE` is the only required application secret. OpenRouter sign-in
  uses PKCE and keeps the resulting key in the visitor's session, so no
  provider credential lives in the cluster.
