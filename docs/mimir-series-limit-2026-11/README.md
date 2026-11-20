# Limite de séries Mimir — novembre 2026

## Symptôme

Le dashboard « Trivy Operator Dashboard » affiche « No data » alors que
Prometheus scrape bien trivy-operator (`up{job="trivy-operator"} == 1`).

## Diagnostic (2026-11-19)

- Le ingester Mimir était exactement à **150 000 séries**, la valeur par
  défaut de `max_global_series_per_user` (non surchargée dans
  `apps/mimir/helm/values.yaml`).
- Le distributeur journalisait en boucle :
  `per-user series limit of 150000 exceeded (err-mimir-max-series-per-user)`.
- Les remote-write sont partiellement ingérés : les séries **existantes**
  continuent à être mises à jour, mais les **nouvelles** séries sont
  rejetées. Le pod trivy-operator ayant été redémarré (~20 h auparavant),
  ses séries portent de nouvelles valeurs `instance`/`pod` → toutes
  rejetées. Les dernières données trivy dans Mimir s'arrêtent à 02:45 UTC.
- Plus gros contributeur : `policy_report_result` (~42 400 séries), suivi
  par `pve_ha_state` (~8 900) et `pve_lock_state` (~7 000).
- Cause indirecte écartée : la PR #695 (orgs Grafana), fusionnée à 21:29 UTC,
  soit bien après la disparition des données.

## Correction

`apps/mimir/helm/values.yaml` :

```yaml
mimir:
  structuredConfig:
    limits:
      max_global_series_per_user: 300000
```

La config runtime n'est pas branchée sur le chart (pas de
`-runtime-config.file` dans les args), donc le changement nécessite un
**rollout du StatefulSet `mimir-ingester`** — ArgoCD le fait normalement
via le checksum de ConfigMap.

## Vérifications

```bash
# 1. La limite est bien appliquée
kubectl get configmap -n monitoring mimir-config -o jsonpath='{.data.mimir\.yaml}' \
  | grep max_global_series_per_user

# 2. Plus d'erreur de limite dans le distributeur
kubectl logs -n monitoring deploy/mimir-distributor --since=15m \
  | grep err-mimir-max-series-per-user   # doit être vide

# 3. Les métriques trivy reviennent dans Mimir (requête via le query-frontend)
curl -sG --data-urlencode 'query=count(trivy_image_vulnerabilities)' \
  http://localhost:18080/prometheus/api/v1/query
```

Le trou de données déjà passé n'est pas comblé : les panels se remplissent
progressivement au rythme des scrapes (60 s). Mémoire ingester attendue :
~1,1 Gi pour 300 k séries au ratio actuel ; les nœuds ont ~24–28 Gi utilisés
sur ~64 Gi.

## Suivi possible (non fait ici)

Réduire la cardinalité à la source plutôt que de continuer à monter la
limite : `write_relabel_configs` côté Prometheus pour écrêter
`policy_report_result`, ou limites de labels dans policy-reporter.
