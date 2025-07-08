# Disaster Recovery Process

## Restoring Nextcloud

Restore a fully functional Nextcloud instance including:

* Config directory (e.g., `config/config.php`)
* Data directory
* Theme directory
* CNPG PostgreSQL Database

1. Put Nextcloud into maintenance mode

    ```bash
    kubectl exec -n nextcloud $(kubectl get pod -n nextcloud -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- php occ maintenance:mode --on
    ```

2. Restore PVC Data using
  [Velero](https://velero.io/docs/main/restore-reference/)

    The following step will restore from latest successful schedule. If you want
    to restore from a specific backup, use the `--from-backup` flag instead.

    ```bash
    velero restore create nextcloud-restore \
    --from-schedule nextcloud-velero-schedule \
    --include-namespaces nextcloud
    ```

    To restore into a different namespace, use the `--namespace-mappings` flag.

    ```bash
    velero restore create nextcloud-restore \
    --from-backup nextcloud-backup \
    --namespace-mappings nextcloud:nextcloud-bk
    ```

3. Restore PostgreSQL Database via CNPG

    ```bash
    kubectl apply -f - <<EOF
    apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    metadata:
      name: postgresql-nextcloud-restore
    spec:
      imageName: ghcr.io/cloudnative-pg/postgresql:16.9
      instances: 3
      bootstrap:
        recovery:
          backup:
            name: cnpg-backup-schedule-<date>
        barmanObjectStore:
          destinationPath: "s3://k8s-shared-bucket/postgresql-nextcloud"
          endpointURL: "https://s3.ca-east-006.backblazeb2.com"
          s3Credentials:
            accessKeyId:
              name: b2-creds
              key: ACCESS_KEY_ID
            secretAccessKey:
              name: b2-creds
              key: ACCESS_SECRET_KEY
        retentionPolicy: "30d"
      storage:
        size: 50Gi
        storageClass: cephfs
    ```

4. Reset Data Fingerprint [(if backup was
   outdated)](https://docs.nextcloud.com/server/latest/admin_manual/maintenance/restore.html#synchronising-with-clients-after-data-recovery)

    ```bash
    kubectl exec -n nextcloud $(kubectl get pod -n nextcloud -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- php occ maintenance:data-fingerprint
    ```

5. Filesystem Rescan

    ```bash
    kubectl exec -n nextcloud $(kubectl get pod -n nextcloud -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- php occ files:scan --all
    ```

    If you get an error like :

    ```txt
    Home storage for user admin not writable or 'files' subdirectory missing
    User folder /var/www/html/data/admin/ is not writable, folders is owned by root and has mode 42700
    Make sure you're running the scan command only as the user the web server runs as
    ```

    you can fix it by running the following command:

    ```bash
    kubectl exec -n nextcloud $(kubectl get pod -n nextcloud -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- chown -R www-data:www-data /var/www/html/data
    kubectl exec -n nextcloud $(kubectl get pod -n nextcloud -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- php occ files:scan --all
    ```

6. Exit Maintenance Mode

    ```bash
    kubectl exec -n nextcloud $(kubectl get pod -n nextcloud -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}")-- php occ maintenance:mode --off
    ```

7. If testing on nextcloud-bk instance, use this one liner to update trusted domain that gets overwritten by restoring the backup:

    ```bash
    kubectl exec -n nextcloud-bk $(kubectl get pod -n nextcloud-bk -l app.kubernetes.io/name=nextcloud -o jsonpath="{.items[0].metadata.name}") -- sed -i "/'trusted_domains' =>/,/),/c\  'trusted_domains' => \n  array (\n    0 => 'nextcloud.bk.shared.cedille.club',\n  )," /var/www/html/config/config.php
    ```

    You can then test with admin login using url <https://nextcloud.bk.shared.cedille.club/login?direct=1>.

## Validation Checklist

* [ ] Can log in as admin
* [ ] Files are visible and downloadable
* [ ] Installed apps and theming are functional
* [ ] Clients are syncing correctly
