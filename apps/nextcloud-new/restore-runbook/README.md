# Disaster Recovery — instance Nextcloud autoritative (`nextcloud-new`)

Depuis le 2026-11-23 (#719), c'est cette instance qui sert
`nextcloud.etsmtl.club` (Collabora : `collabora-nextcloud.etsmtl.club`). Le
runbook de l'ancienne instance est dans `apps/nextcloud/restore-runbook/` et
doit être ignoré après son décommissionnement prévu le 2026-12-01.
Pour l'état global des migrations : `docs/nextcloud-migration-2026-09/README.md`.

## Périmètre des backups

| Donnée | Emplacement | Couverture |
|---|---|---|
| `config.php`, apps, thème | PVC `nextcloud-pvc` (20 Gi, `cephfs` RWX, namespace `nextcloud-new`) | Velero `nextcloud-new-velero-schedule`, quotidien 06:35, TTL 7 j. Le pod porte `app.kubernetes.io/backup: velero` et `backup.velero.io/backup-volumes: nextcloud-main` (défini dans `kustomization.yaml`). |
| Base PostgreSQL | CNPG `postgresql-nextcloud` (namespace `nextcloud-new`) | `ScheduledBackup` `cnpg-backup-schedule` (06:40, rétention 30 j) via barman-cloud vers `s3://k8s-shared-bucket/postgresql-nextcloud-new` sur B2. **Archive distincte** de l'ancienne instance (`.../postgresql-nextcloud`). |
| Fichiers utilisateurs | Bucket S3 GarageHQ `nextcloud-data` (`10.0.21.50:3900`) | **Pas dans Velero** : répliqués vers B2 par le CronJob `nextcloud-data-backup` (06:30, miroir `s3://k8s-shared-bucket/nextcloud-data-backup/`, versions supprimées/remplacées des 7 derniers jours dans `.../nextcloud-data-backup-changes/<date>/`). |

Un restore Velero seul ne restaure donc que la configuration et le code applicatif,
pas les fichiers des utilisateurs.

> **Attention aux `subPath` (piège du 2026-11-24).** Le chart monte le PVC via
> des `subPath` : dans le pod Nextcloud, `/var/www/html/config` est le `subPath`
> `config` du PVC, `/var/www/html/custom_apps` est `custom_apps`, etc. Si on monte
> le PVC directement sur `/var/www` dans un pod de diagnostic/backup, le vrai
> `config.php` est donc à `/var/www/config/config.php` (et **pas**
> `/var/www/html/config/config.php`, répertoire vide hérité du clone de
> l'ancienne instance). Une archive qui ne contient que `html/` perd le
> `config.php` et les `custom_apps/`. Voir le compte rendu de l'incident dans
> `docs/nextcloud-migration-2026-09/README.md`.

## Restauration des fichiers utilisateurs (bucket Garage)

Le CronJob de backup ne restaure rien automatiquement. Si des objets manquent
dans `nextcloud-data` :

1. Appliquer le Job manuel (non géré par ArgoCD, présent uniquement dans le
   repo) :

    ```bash
    kubectl -n nextcloud-new apply -f apps/nextcloud-new/restore-runbook/restore-job.yaml
    kubectl -n nextcloud-new logs -f job/nextcloud-data-restore
    ```

    Par défaut, il recopie le miroir courant B2 vers Garage avec `rclone copy`
    (non destructif : les fichiers présents dans Garage mais absents de B2 ne
    sont pas supprimés). Pour récupérer une version supprimée ou remplacée,
    éditer `RESTORE_SOURCE` dans le manifeste pour pointer vers
    `nextcloud-data-backup-changes/<date>` avant de l'appliquer.

2. Une fois le Job terminé, relancer l'étape 5 (`files:scan --all`) pour que
   Nextcloud réindexe les fichiers restaurés.

## Restauration

1. **Mode maintenance** (une des 3 répliques suffit) :

    ```bash
    kubectl -n nextcloud-new exec $(kubectl get pod -n nextcloud-new -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- php occ maintenance:mode --on
    ```

2. **Restaurer le PVC config/apps** depuis le dernier backup du schedule dédié
   (ou `--from-backup <nom-du-backup>` pour un backup précis) :

    ```bash
    velero restore create nextcloud-new-restore \
      --from-schedule nextcloud-new-velero-schedule \
      --include-namespaces nextcloud-new
    ```

    Pour tester dans un namespace séparé, ajouter
    `--namespace-mappings nextcloud-new:nextcloud-new-bk` — ce namespace de test
    n'existe pas dans le repo et doit être créé avec ses propres manifests
    (Application ArgoCD, secrets, PVC) avant le restore.

3. **Restaurer la base PostgreSQL** via CNPG. Lister d'abord les backups
   disponibles : `kubectl -n nextcloud-new get backups.postgresql.cnpg.io`.
   Puis créer un cluster de récupération :

    ```yaml
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: postgresql-nextcloud-restore
      namespace: nextcloud-new
    spec:
      imageName: ghcr.io/cloudnative-pg/postgresql:16.9
      instances: 3
      bootstrap:
        recovery:
          backup:
            name: cnpg-backup-schedule-<date>
        barmanObjectStore:
          destinationPath: "s3://k8s-shared-bucket/postgresql-nextcloud-new"
          endpointURL: "https://s3.ca-east-006.backblazeb2.com"
          s3Credentials:
            accessKeyId:
              name: b2-creds
              key: ACCESS_KEY_ID
            secretAccessKey:
              name: b2-creds
              key: ACCESS_SECRET_KEY
          wal:
            compression: gzip
            encryption: AES256
      storage:
        size: 50Gi
        storageClass: ceph-rbd
    ```

    La taille ci-dessus est celle d'un cluster de test ; pour remplacer la
    production, reprendre 105 Gi et `walStorage: 20Gi` de
    `apps/nextcloud-new/resources/postgresql.yaml`. Ne **jamais** réutiliser le
    chemin B2 `.../postgresql-nextcloud` (celui de l'ancienne instance).

4. **Vérifier `trusted_domains`** après restauration — le `config.php` du PVC
   sauvegardé peut contenir des entrées historiques :

    ```bash
    kubectl -n nextcloud-new exec $(kubectl get pod -n nextcloud-new -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- php occ config:system:get trusted_domains
    ```

    La liste doit contenir `nextcloud.etsmtl.club` et, jusqu'au 2026-11-30,
    peut encore contenir `new-nextcloud.etsmtl.club`. Passé cette date, retirer
    cette dernière (`occ config:system:delete trusted_domains <index>`), puis
    nettoyer le commentaire dans `helm/nextcloud-values.yaml`. Ne pas ajouter
    `old-nextcloud.etsmtl.club` à l'instance autoritative.

5. **Fingerprint et scan** (le scan peut être long : les fichiers sont sur S3) :

    ```bash
    kubectl -n nextcloud-new exec $(kubectl get pod -n nextcloud-new -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- php occ maintenance:data-fingerprint
    kubectl -n nextcloud-new exec $(kubectl get pod -n nextcloud-new -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- php occ files:scan --all
    ```

6. **Vérifier Collabora**, puis **sortir du mode maintenance** :

    ```bash
    kubectl -n nextcloud-new exec $(kubectl get pod -n nextcloud-new -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- php occ config:app:get richdocuments wopi_url
    # attendu : https://collabora-nextcloud.etsmtl.club
    kubectl -n nextcloud-new exec $(kubectl get pod -n nextcloud-new -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- php occ maintenance:mode --off
    ```

## Validation

- [ ] Connexion admin sur <https://nextcloud.etsmtl.club>
- [ ] Fichiers visibles et téléchargeables (accès GarageHQ `nextcloud-data` OK)
- [ ] Dernier Job `nextcloud-data-backup` réussi et miroir B2 présent
- [ ] Ouverture d'un document via Collabora (`collabora-nextcloud.etsmtl.club`)
- [ ] Apps, thème et sites externes (ConfigMap `nextcloud-setup-job`) fonctionnels
- [ ] Clients de synchronisation reconnectés (fingerprint correct)
- [ ] `trusted_domains` propre (voir étape 4)
