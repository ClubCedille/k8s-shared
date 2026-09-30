# Deployment structure report

Audit of how applications are laid out across the Cedille GitOps repositories,
with the outliers called out and a target layout to converge on.

- **Date:** 2026-09-30
- **Scope:** `k8s-shared`, `k8s-cedille-production-v2`, `k8s-cedille-sandbox`
  (application manifests). `k8s-base` / `k8s-foundation` (cluster platform)
  mentioned only where they interact.
- **Method:** every `*.argoapp.yaml` in the three repos parsed for its source
  path, destination namespace and project; every `kustomization.yaml` classified
  by shape; results cross-checked against the 131 `Application` objects actually
  registered in the k8s-shared ArgoCD.

---

## 1. The clusters and their repos

| Repo | Cluster | Applications |
|---|---|---|
| `k8s-shared` | `k8s-shared` (dev/shared) | 69 |
| `k8s-cedille-production-v2` | `k8s-cedille-production-v2` (prod) | 36 |
| `k8s-cedille-sandbox` | `k8s-cedille-sandbox` | 3 |
| `k8s-foundation` | all (cluster platform) | 11 |

Each repo's Applications hard-code its own cluster as `destination.server`, so
the **same namespace is targeted by both `k8s-shared` and
`k8s-cedille-production-v2`** for 30 apps. This is intentional parallelism, not
a conflict — but see §4.1, because the directory layouts then diverge.

---

## 2. Regular (non-Helm) deployments

The dominant shape, and a good one:

```
apps/clubs/<club>/<app>/base/      shared, environment-agnostic manifests
apps/clubs/<club>/<app>/prod/     overlay: resources: ../base + env deltas
```

`base/` is never an ArgoCD target; it is pulled in by the overlay via
`resources: - ../base`. That is the case for 47 of the directories in
`k8s-shared`.

Env dirs in use: `base`, `prod`, `dev`, `staging`. Consistent, no
`development`/`production` variants.

Conventions that are already solid and worth keeping:

- Each overlay carries its own `<app>.argoapp.yaml` next to the manifests.
- Every Application uses `CreateNamespace=true`, `automated.selfHeal: true`
  and `automated.prune: true`.
- Ingress is uniformly `Contour` + cert-manager via HTTPProxy (see §6).

---

## 3. Helm deployments

Helm apps follow **four different shapes**, which is the main source of
incoherence in this repo.

### Shape A — vendored chart + `helm/values.yaml`, inflated by kustomize
```
apps/<app>/charts/<chart>-<version>/     vendored chart
apps/<app>/helm/values.yaml              values
apps/<app>/kustomization.yaml            helmCharts: {...}
```
`authentik`, `matomo`, `scm-manager`, `penpot`, `exutoire/supabase`.
**This is the best-defined shape and should be the target.**

### Shape B — remote chart, values in `helm/values.yaml`
```
apps/<app>/helm/values.yaml
apps/<app>/kustomization.yaml            helmCharts: {repoURL, ...}
```
`grafana`, `loki`, `mimir`, `netbox`, `alloy-logs`, `nextcloud`,
`nextcloud-new`, `crd-schema-publisher`, `system/argocd`, `forgejo`.
Identical to A minus the vendored chart — a legitimate variant, but it means
"where is the chart version pinned?" has two different answers.

### Shape C — chart rendered into the repo, used as a plain kustomize base
```
apps/patchets/base/charts/postgresql-16.4.16/    committed rendered output
```
No `helmCharts:`, no `helm/`. Not a Helm deployment at all — a snapshot of one.
Diverges silently from the chart it was rendered from.

### Shape D — pure ArgoCD Helm source, no kustomize involved
```yaml
sources:
  - chart: coder
    repoURL: https://...
```
`apps/coder/resources`, `apps/planka/resources`, and `data-acq` (multi-source
influxdb2 + grafana). Values live inside the `.argoapp.yaml`, and the directory
is named `resources/` but contains no kustomization.

**Additionally inconsistent:** `capra`, `sonia` and `synapsets` wiki charts
vendored under `charts/wiki-2.2.17/` but with their values inlined in the
kustomization via `valuesInline:` instead of `helm/values.yaml` — Shape A with
the values half moved.

---

## 4. Outliers

Ranked by how much they cost you.

### 4.1 The same app lives under different paths in each cluster repo
30 namespaces are deployed by both `k8s-shared` and `k8s-cedille-production-v2`,
and the paths do not match. Beyond the expected `clubs/` prefix difference:

| Namespace | k8s-shared | production-v2 | Problem |
|---|---|---|---|
| `comets` | `clubs/comets/website/prod` | `comets/siteweb/prod` | `website` vs `siteweb` |
| `conjure-site` | `clubs/conjure/website/prod` | `conjure/site/prod` | `website` vs `site` |
| `synapsets` | `clubs/synapsets/website/prod` | `synapsets/web/prod` | `website` vs `web` |
| `webapp-dronolab` | `clubs/dronolab/website/prod` | `dronolab/webApp/prod` | `website` vs `webApp` (camelCase) |

And 8 apps lose their app-name segment entirely in production-v2 —
`apps/cedille/prod` rather than `apps/cedille/website/prod`, likewise
`esports`, `etshub`, `forom`, `ingenieuses`, `integrale`, `saveursdegenie`,
`trema`.

The cost is concrete: any change to a shared app must be found and applied
twice, under two different names, and nothing in either repo makes that visible.

### 4.2 Six live Applications have no manifest in any repo
Registered in ArgoCD, with real namespaces serving traffic, but no
`*.argoapp.yaml` anywhere in the three repos:

| Application | Path | Namespace |
|---|---|---|
| `authentik` | `apps/authentik` | `authentik` |
| `matomo` | `apps/matomo` | `matomo` |
| `netbox` | `apps/netbox` | `netbox` |
| `k8s-shared-nextcloud` | `apps/nextcloud` | `nextcloud` |
| `k8s-shared-nextcloud-new` | `apps/nextcloud-new` | `nextcloud-new` |
| `k8s-shared-velero-backup` | `system/backups` | `velero` |

These are unreproducible: a fresh ArgoCD, or a rebuild from the repo alone,
would not bring them back. This is the highest-severity finding in the audit.

### 4.3 Application name suffix `-shared` applied to 30 of 72 apps
`markets-shared`, `trema-shared`, `esports-shared`… versus `littlelink`,
`grafana`, `forgejo`, `netbox` with no suffix. The suffix does not disambiguate
anything today, since each cluster's ArgoCD only registers its own repo's apps.
It is historical residue that makes the app list harder to scan.

### 4.4 ArgoCD projects are fragmented
9 projects for 131 Applications: `k8s-shared` (84), `k8s-cedille-sandbox` (18),
`k8s-poc` (11), `lanets` (7), `applets` (6), `algoets` (2), `common`,
`k8s-foundation`, `conjure` (1 each). Most apps should be in the repo's own
project; the single-app projects add no value.

### 4.5 Directories named `ingress.yaml` that contain HTTPProxy
Pre-existing, untouched by the conversion in §6: `preview-base/ingress.yaml`,
`apps/clubs/preci/wordpress/prod/ingress.yaml`,
`apps/clubs/veloom/wordpress/prod/ingress.yaml`,
`system/argocd/resources/ingress.yaml`, `apps/clubs/crd-schema-publisher/`.
Misleading now that HTTPProxy is the standard.

### 4.6 `data_acq` uses a raw directory as an ArgoCD source
`apps/clubs/comets/data_acq/resources` is referenced directly as an ArgoCD
`path` with **no `kustomization.yaml`** — the only application in either repo
that does this (the other two, `coder` and `planka`, are Shape D Helm apps, so
they have a reason). Everything else goes through kustomize.

### 4.7 Naming oddities
- `apps/clubs/veloom/wordpress/prod/staging-ingress.yaml` serves
  `evovelo.prodv2.cedille.club` — "veloom" directory, "evovelo" hostname, and a
  file called "staging" inside `prod`.
- `apps/forgejo/base`, `apps/matomo/prod/mariadb`, `apps/kubero-ui/{base,prod}`
  are not referenced by any Application. `apps/kubero-operator` and
  `system/backups` likewise (`velero-backup` exists only in-cluster, see §4.2).
- `apps/nextcloud` and `apps/nextcloud-new` both present, both live, no marker of
  which is authoritative.

### 4.8 `etsmtl.ca` is not covered by any external-dns instance
`k8s-base/common/external-dns` is scoped to `etsmtl.club` and
`external-dns-cedille` to `cedille.club`. Hosts on `etsmtl.ca`
(`wiki.capra`, `conjure`, `synapsets`, `saveursdegenie`, `cedille`, plus apexes
like `habitek.ca`) get no record management. Adding a hostname there is a manual
Cloudflare step that no manifest can express. Both instances are
`policy: upsert-only`, so nothing is ever deleted — the gap is creation only.

---

## 5. Target layout

Two shapes, and only two.

**Regular:**
```
apps/clubs/<club>/<app>/base/       shared manifests
apps/clubs/<club>/<app>/prod/      overlay + <app>.argoapp.yaml
```

**Helm — one shape, Shape A:**
```
apps/<app>/charts/<chart>-<version>/   vendored, version pinned
apps/<app>/helm/values.yaml            values
apps/<app>/kustomization.yaml          helmCharts:
apps/<app>/prod/<app>.argoapp.yaml     (if multi-env)
```

Rules to make it hold:

1. **Every** app is `base/` + at least one env overlay. No env-less app dirs
   (`grafana`, `loki`, `netbox`, `scm-manager`, `pkg-cache`, `etsmtl-club`,
   `vault-gh-roles`, `distro-mirror` are single-instance and can use `prod/`).
2. **Every** app is reached through a `kustomization.yaml`. No raw directory
   sources.
3. **Every** Application lives in the repo as a `<app>.argoapp.yaml`, in the
   repo's own ArgoCD project, with no `-shared` suffix.
4. Identical app → identical relative path across cluster repos, so
   `apps/clubs/<club>/<app>/<env>` in both. Fix the 4 name divergences in §4.1
   and restore the app-name segment for the 8 apps that lost it.
5. Helm values always in `helm/values.yaml`; never `valuesInline`, never Shape C
   rendered snapshots.
6. Files named after what they contain: `httpproxy.yaml`, `certificate.yaml`.

---

## 6. Change already made in this working tree

As part of this task, all 37 `networking.k8s.io/v1` `Ingress` manifests in
`k8s-shared` were converted to Contour `HTTPProxy` + explicit cert-manager
`Certificate`, matching the pattern already used by `authentik`, `vaultwarden`
and `outlinewiki`.

- 37 files → 47 `HTTPProxy` + 46 `Certificate`, across 34 overlay directories.
- All 46 TLS secret names were **preserved**, so no certificate is re-issued and
  no traffic is interrupted by cert churn.
- Both external-dns instances already list `contour-httpproxy` in `sources` and
  run `policy: upsert-only`, so DNS records are neither dropped nor orphaned.
- Multi-backend routes (`markets`, `planifets`) were emitted with longest-prefix
  first and the `/` catch-all last, since HTTPProxy matches routes in order.
- Verified by rendering every overlay before and after and diffing host, service,
  port, TLS secret and issuer: 29/29 buildable overlays identical, plus 5
  blocked only by remote Helm chart downloads, verified at file level.

---

## 7. Suggested order of work

1. **Add the 6 missing `argoapp.yaml` files** (§4.2). Smallest change, removes
   the only unreproducible state. Do this first.
2. **Fix the 4 hostname/path divergences** (§4.1) and restore the 8 app-name
   segments. Mechanical `git mv`, one PR per repo, no manifest edits.
3. **Rename the misleading `ingress.yaml` files** (§4.5). Trivial.
4. **Collapse the Helm shapes** (§3) onto Shape A. Largest change; do it app by
   app, starting with the two `nextcloud` copies and deciding which is
   authoritative at the same time.
5. **Normalise ArgoCD projects and drop `-shared`** (§4.3, §4.4).
6. **Decide `etsmtl.ca`** (§4.8): add an external-dns instance for the zone, or
   document the manual step in the app README.