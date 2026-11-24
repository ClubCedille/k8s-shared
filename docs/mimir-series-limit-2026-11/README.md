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

Le filtre `write_relabel_configs` ajouté entre-temps dans
`apps/prometheus/helm/values.yaml` (PR #709) supprime déjà l'essentiel du
bruit (`policy_report_result` et quelques buckets HTTP/JDBI/Dex) avant le
remote-write : la limite à 300 k reste une marge pour les pics de
cardinalité, et non le seul correctif.

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

## Suivi possible

Si la cardinalité repart à la hausse, réduire à la source plutôt que de
continuer à monter la limite : le filtre `write_relabel_configs` est déjà en
place (PR #709) ; la suite consistait à limiter les labels de
`policy_report_result` dans policy-reporter.

## Suite 2026-11-24 : PVC ingester saturé

La PR #711 a porté la limite à **600 000** séries et réintégré
`policy_report_result` (~69k séries) dans le remote-write. Prometheus a été
dimensionné en conséquence (2 CPU / 4Gi) et la target `kube-state-metrics` est
enfin `up` (scrape ~0,5 s). En revanche, le volume de l'ingester est resté au
défaut du chart (**2 Gi**) : à ~03:06 UTC le WAL a saturé
(`write to WAL: ... no space left on device`), le distributeur a renvoyé des
500 en boucle et toute ingestion récente a été perdue.

### Procedure de resize

La StorageClass `ceph-rbd` autorise l'extension (`allowVolumeExpansion: true`).
Deux étapes sont nécessaires car `spec.volumeClaimTemplates` d'un StatefulSet
est **immutable** :

1. Dans le Git : `ingester.persistentVolume.size: 20Gi` dans
   `apps/mimir/helm/values.yaml`. Le champ est ignoré cote StatefulSet via
   `ignoreDifferences` dans `apps/mimir/mimir.argoapp.yaml` (avec
   `RespectIgnoreDifferences=true`) pour ne pas faire échouer les syncs.
2. Sur le cluster, agrandir le PVC existant (opération manuelle unique) :

```bash
kubectl patch pvc -n monitoring storage-mimir-ingester-0 \
  --type=merge -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
kubectl get pvc -n monitoring storage-mimir-ingester-0   # CAPACITE 20Gi
kubectl logs -n monitoring deploy/mimir-distributor --since=5m \
  | grep -c 'no space left'   # doit rester a 0
```

Le trou de données entre ~03:06 UTC et le resize n'est pas comblé : les panels
se remplissent progressivement. Un redemarrage du pod `mimir-ingester-0` peut
etre necessaire pour que le filesystem monté voie la nouvelle taille selon le
comportement du CSI.
