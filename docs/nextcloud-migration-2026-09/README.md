# Nextcloud 2026 — état de la migration et index documentaire

**Mis à jour le 2026-11-23.** Ce fichier est la source de vérité pour l'état des
projets Nextcloud 2026. Les autres documents de ce dossier et d'ailleurs dans le
repo sont soit opérationnels, soit historiques : leurs dates ne doivent pas être
lues comme l'état actuel.

## État autoritatif

La source de vérité reste les manifests GitOps (`resources/httpproxy.yaml`,
`resources/certificate.yaml`, `helm/*-values.yaml`, `resources/nextcloud-setup.bash`
de chaque app). Résumé au 2026-11-23 :

| | Instance historique | Instance actuelle |
|---|---|---|
| Application ArgoCD | `k8s-shared-nextcloud` | `k8s-shared-nextcloud-new` |
| Namespace | `nextcloud` | `nextcloud-new` |
| Domaine Nextcloud | `old-nextcloud.etsmtl.club` | `nextcloud.etsmtl.club` |
| Domaine Collabora | `old-collabora-nextcloud.etsmtl.club` | `collabora-nextcloud.etsmtl.club` |
| Image Nextcloud | `33.0.10-apache` | `35.0.3-apache` |
| Image Collabora | `24.04.13.3.1` (chart `1.3.8`) | `26.04.6.2.1` (chart `1.3.9`) |
| Schedule Velero | `nextcloud-velero-schedule` (jusqu'au 2026-12-01) | **`nextcloud-new-velero-schedule`** |
| Archive B2 (CNPG) | `.../postgresql-nextcloud` | `.../postgresql-nextcloud-new` |
| Backup fichiers (Garage) | données dans le PVC 30 Ti (CephFS, dans Velero) | **`nextcloud-data-backup`** : rclone → B2, quotidien, rétention 7 j |
| Rôle | rollback jusqu'au 2026-11-30, décommission le 2026-12-01 | **autoritative** |

> **À propos de l'« adoption » des backups :** les backups Velero existants
> restent liés à leur schedule et à leur namespace d'origine — on ne peut pas
> transférer leur historique à la nouvelle instance. Ce qui est adopté, c'est
> la **couverture** : un schedule dédié `nextcloud-new-velero-schedule`, une
> archive CNPG distincte et un CronJob `rclone` pour le bucket Garage (Velero ne
> sait pas sauvegarder un S3 externe). Restaurer l'ancien PVC dans `nextcloud-new`
> serait contre-productif (config.php 33.x, données CephFS alors que la nouvelle
> instance lit ses fichiers dans Garage).

Le basculement a été effectué dans #719 (2026-11-23) : l'ancienne instance a
pris `old-nextcloud.*` / `old-collabora-nextcloud.*`, la nouvelle a repris
`nextcloud.*` / `collabora-nextcloud.*`. Les deux instances restent déployées
jusqu'au 2026-12-01 ; entre-temps, seule `nextcloud-new` doit être considérée
comme le service de production.

> Les anciens noms `new-nextcloud.etsmtl.club` et `new-collabora-nextcloud.etsmtl.club`
> n'existent plus dans les manifests. Le seul endroit où `new-nextcloud` subsiste
> est le commentaire `trustedDomains` de `apps/nextcloud-new/helm/nextcloud-values.yaml`,
> qui documente une entrée encore présente dans `config.php` sur le PVC pendant la
> fenêtre de rollback. À retirer le 2026-11-30 (voir ci-dessous).

## Chronologie

- **Septembre 2026 (stockage).** Migration du contenu Nextcloud de CephFS vers
  Garage (bucket `nextcloud-data`, ~8 To). Voir `analyse-tiering-ceph-garage.md`.
- **2026-09-04 → 09-12 (tiering).** Expérimentation d'un étage chaud Ceph RGW /
  froid Garage via la storage class `GARAGE_COLD`. Révoquée à la suite du bug
  Ceph [tracker#80309](https://tracker.ceph.com/issues/80309) ; l'ObjectBucketClaim
  et le Job de lifecycle ont été supprimés le 2026-09-19 (#493). **Aucun tiering
  n'est actif sur Nextcloud aujourd'hui** : `OBJECTSTORE_S3_*` pointe directement
  vers GarageHQ. `GARAGE_COLD` reste utilisé par d'autres apps (voir
  `apps/distro-mirror/docs/lifecycle-runbook.md`).
- **2026-11-22 (#708).** Instance `nextcloud-new` activée (retrait des patches de
  maintenance : redirect, replicas 0, crons suspendus, setup job no-op), montée
  en Nextcloud 35 et Collabora 26.
- **2026-11-23 (#719, #720, #721).** Switchover des domaines, avec passage
  intermédiaire par Nextcloud 34.0.4 (#720) avant la version finale 35.0.3 (#721)
  — Nextcloud refuse un saut direct 33 → 35.
- **2026-11-23 (backup).** Ajout d'un schedule Velero dédié à `nextcloud-new`
  (`system/backups/nextcloud-new.yaml`) et d'un runbook de restore pour
  l'instance autoritative. Les deux schedules coexistent jusqu'au 2026-12-01.
- **2026-11-23 (bucket S3).** Velero ne pouvant pas couvrir un bucket externe,
  ajout d'un CronJob `rclone` quotidien répliquant `nextcloud-data` (Garage) vers
  B2, avec une rétention de 7 jours alignée sur Velero, et d'un Job de
  restauration manuel. Voir `apps/nextcloud-new/restore-runbook/`.
- **2026-11-24 (incident PVC).** Le PVC `nextcloud-pvc` de `nextcloud-new` était
  un clone de l'ancienne instance, dimensionné à 30 Ti alors que le manifeste
  demande 20 Gi — ArgoCD bouclait sur un patch de réduction interdit. Le volume
  a été sauvegardé puis supprimé/recréé à 20 Gi. Voir la section dédiée ci-dessous.

## Incident du 2026-11-24 — recréation du PVC `nextcloud-new`

**Contexte.** Le sync ArgoCD (bloqué depuis le 18/11 sur la santé CNPG) a
finalement échoué sur
`PersistentVolumeClaim "nextcloud-pvc" is invalid: spec.resources.requests.storage:
Forbidden: field can not be less than status.capacity` : le PVC live faisait
30 Ti (clone de l'ancienne instance, données de 2025 à la racine) alors que le
manifeste n'a jamais demandé que 20 Gi depuis #347. Le merge de #726 (30 Ti)
avait débloqué le sync, puis #727 a restauré 20 Gi avant l'opération.

**Piège rencontré.** Le chart Nextcloud monte le PVC avec des `subPath` :
dans un pod qui monte directement le PVC sur `/var/www`, le `config.php` actif
est dans `/var/www/config/` (monté à `/var/www/html/config` dans le pod
Nextcloud), **pas** dans `/var/www/html/config/` (qui est un répertoire vide
hérité du clone). La première archive ne contenait que `html/` et `tmp/` et a
donc manqué `config.php` et `custom_apps`. Ils ont été récupérés sur l'ancienne
instance (encore en service jusqu'au 2026-12-01) avant sa suppression :
`instanceid` identique (`ocxmn448j6gf`), donc les chemins S3 restent valides.

**Actions réalisées.**
1. Sync ArgoCD mis en manuel, `deploy/nextcloud` à 0 répliques, cron suspendu.
2. Archive de `/var/www` (hors caches `preview`, inaccessibles sur CephFS) vers
   `s3://k8s-shared-bucket/nextcloud-new-pvc-backup/2026-11-24-pre-recreate-final.tar.gz`.
3. Suppression des anciens pods de cron qui retenaient le PVC, puis du PVC
   (`reclaimPolicy: Delete`), recréation à **20 Gi** depuis le manifeste.
4. Restauration de `html/` et `tmp/` depuis l'archive, copie de `config.php` et
   `custom_apps/` depuis l'ancienne instance. `config.php` réécrit avec
   `dbhost` sur `nextcloud-new`, `trusted_domains` à jour, `version` forcé à
   `35.0.3.2` (le schéma DB était déjà en 35, l'upgrade 33 → 35 direct est refusé).
5. `occ upgrade`, régénération du `data-fingerprint`, correction du `wopi_url`
   resté sur `new-collabora-nextcloud` (le setup Job n'avait pas été rejoué au
   switchover), puis reprise du deploy (3/3 Ready) et du sync ArgoCD.

**État final :** ArgoCD `Synced / Healthy`, 3/3 pods Ready, CNPG 3/3 healthy et
`ContinuousArchiving=True`, `version=35.0.3.2`, `maintenance=false`,
`needsDbUpgrade=false`. Les 6 backups CNPG du 18→23/11 ont échoué (plugin
barman absent du pod jusqu'au rolling restart du 24/11) ; le premier backup
réussi est attendu le 24/11 à 06:40 UTC.

## Fenêtre de rollback — ferme le 2026-11-30

Les utilisateurs ont une semaine pour valider la nouvelle plateforme. Passé le
2026-11-30, le rollback n'est plus proposé.

### Procédure de rollback (uniquement avant le 2026-11-30)

1. Faire un `git revert a5bdc4c` (le switchover de domaines) sur une branche,
   ouvrir une PR, puis laisser ArgoCD synchroniser. Les commits #720 et #721
   (montée 34 → 35) **ne sont pas à annuler** : il s'agit d'une bascule de
   domaines, pas d'une régression de version.
2. Vérifier les `HTTPProxy` / `Certificate` des deux apps : l'ancienne reprend
   `nextcloud.etsmtl.club` / `collabora-nextcloud.etsmtl.club`, la nouvelle
   repasse sur `new-nextcloud.etsmtl.club` / `new-collabora-nextcloud.etsmtl.club`.
3. Vérifier `trusted_domains` dans le `config.php` des deux PVC et `wopi_url`
   des deux instances : les entrées historiques survivent aux restores et aux
   changements de values.
4. external-dns est en `policy: upsert-only` : les enregistrements sont mis à
   jour mais rien n'est supprimé. Confirmer la résolution DNS après sync.
5. Si le rollback est utilisé, documenter le retour en arrière ici avant le
   2026-12-01 ; sinon, appliquer le nettoyage ci-dessous.

### Nettoyage le 2026-11-30 (fenêtre fermée, pas de rollback)

- [ ] Retirer `new-nextcloud.etsmtl.club` du `config.php` sur le PVC de
      `nextcloud-new` (`occ config:system:get trusted_domains`, puis
      `occ config:system:delete trusted_domains <index>`), et nettoyer le
      commentaire dans `helm/nextcloud-values.yaml`.

## Décommissionnement de l'ancienne instance — 2026-12-01

À condition qu'aucun problème n'ait été remonté pendant la fenêtre de rollback.

- [ ] Supprimer l'Application ArgoCD `k8s-shared-nextcloud` et le répertoire
      `apps/nextcloud/` (y compris son runbook et ses patches).
- [ ] Supprimer `system/backups/nextcloud.yaml` et sa référence dans
      `system/backups/kustomization.yaml` ; vérifier au préalable que
      `nextcloud-new-velero-schedule` a bien produit ses derniers backups.
- [ ] Décider de la rétention de l'archive B2
      `s3://k8s-shared-bucket/postgresql-nextcloud` (ancienne instance) avant
      de la supprimer.
- [ ] Nettoyer manuellement les enregistrements DNS
      `old-nextcloud.etsmtl.club` / `old-collabora-nextcloud.etsmtl.club` :
      external-dns est `upsert-only` et ne les supprimera pas.
- [ ] Vérifier qu'aucune configuration ne pointe encore vers `old-nextcloud`
      (CSP `frame-ancestors`, clients, documentation).
- [ ] Mettre à jour ce fichier pour refléter une instance unique.

## Index des documents

| Document | Portée | État |
|---|---|---|
| `docs/nextcloud-migration-2026-09/README.md` (ce fichier) | état courant, échéances, index | **courant** |
| `apps/nextcloud-new/restore-runbook/README.md` | restore de l'instance autoritative | **courant** |
| `docs/nextcloud-migration-2026-09/analyse-tiering-ceph-garage.md` | analyse de faisabilité du tiering (2026-09-04) | **historique**, solution non retenue |
| `apps/nextcloud-new/docs/rgw-tiering-runbook.md` | expérimentation de tiering RGW/Garage | **historique / clos** — ne pas appliquer |
| `apps/nextcloud/restore-runbook/README.md` | restore de l'ancienne instance | valable jusqu'au 2026-12-01 |
| `docs/deployment-structure/README.md` | audit de structure des repos (2026-09-30) | instantané daté ; voir sa note de mise à jour |
| `apps/maintenance/README.md` | procédure de maintenance PHP | modèle ; patches actuellement retirés de `nextcloud-new` |
| `apps/distro-mirror/docs/lifecycle-runbook.md` | storage class `GARAGE_COLD` (partagée) | courant |

## Sauvegarde des fichiers utilisateurs — vérification initiale

Le bucket Garage `nextcloud-data` (10.0.21.50:3900), hors Velero et hors CNPG,
est désormais répliqué chaque nuit vers B2 par le CronJob `nextcloud-data-backup`
(`apps/nextcloud-new/resources/nextcloud-data-backup-cronjob.yaml`, 06:30,
rétention 7 j alignée sur Velero). Le miroir courant est dans
`s3://k8s-shared-bucket/nextcloud-data-backup/`, les versions supprimées ou
remplacées dans `.../nextcloud-data-backup-changes/<date>/`. La configuration
non secrète est dans `resources/nextcloud-data-backup-config.yaml` et les
credentials viennent des secrets déjà présents dans le namespace.

- [ ] Après la première exécution, confirmer le succès du Job :
      `kubectl -n nextcloud-new get jobs -l app=nextcloud-data-backup` et
      `kubectl -n nextcloud-new logs job/nextcloud-data-backup-<suffixe>`.
- [ ] Vérifier que le miroir B2 contient bien les préfixes attendus
      (`rclone lsd b2:k8s-shared-bucket/nextcloud-data-backup`).
- [ ] Le Job de restauration manuel est
      `apps/nextcloud-new/restore-runbook/restore-job.yaml` (non appliqué par
      ArgoCD).
