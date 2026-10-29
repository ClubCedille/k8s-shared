# Renovate

Self-hosted [Renovate](https://docs.renovatebot.com/) using the
[renovate-operator](https://github.com/mogenius/renovate-operator). The operator
runs Renovate as Kubernetes Jobs and schedules them with a `RenovateJob` CR.

## Scope

Club app images stay on Argo CD Image Updater (`apps/clubs/**`). Renovate is
responsible for:

- container image updates in the non-club apps (`apps/*` and `system/*`),
- Helm chart versions in every `kustomization.yaml` (`helmCharts`),
- GitHub Actions versions.

`renovate.json` at the repository root encodes this split. The club image rules
are deliberately disabled for the `argocd`, `helm-values`, and `kubernetes`
managers, while the `kustomize` `HelmChart` dependency type remains enabled so
chart versions still get PRs.

## Credentials

The GitHub token lives in Vault at
`kv/data/renovate-operator/default/github-token` (keys `GITHUB_COM_USER`,
`GITHUB_COM_TOKEN`, `RENOVATE_TOKEN`). `vault-secret.yaml` syncs it into the
`renovate-operator` namespace as `renovate-secret`. The Vault policy is scoped to
the namespace and service account, so the path must match
`kv/data/<namespace>/<service-account>/*`.

## Usage

The `RenovateJob` runs daily at 03:00 America/Toronto. To trigger discovery or
a run immediately:

```sh
kubectl -n renovate-operator annotate renovatejob k8s-shared \
  renovate-operator.mogenius.com/discovery=true
kubectl -n renovate-operator annotate renovatejob k8s-shared \
  renovate-operator.mogenius.com/schedule-all=true
```

Open the UI with:

```sh
kubectl -n renovate-operator port-forward svc/renovate-operator 8081:8081
```

The UI is unauthenticated and only exposed as a ClusterIP service. Add
`route.enabled` (Contour/Gateway API) or enable OIDC in the chart values before
exposing it outside the cluster.
