# Maintenance page

Static nginx page served at <https://maintenance.etsmtl.club>. It does not run
PHP.

## Security maintenance procedure

> **État actuel (2026-11-23).** Les patches décrits ci-dessous ont été retirés de
> `apps/nextcloud-new` lorsque l'instance a été activée (#708, 2026-11-22) : ni
> le redirect, ni les replicas à 0, ni les crons suspendus, ni le setup job
> no-op ne sont présents dans le repo. Cette section décrit donc un **modèle de
> procédure à réappliquer** lors d'une fenêtre de maintenance, pas l'état
> courant. Elle s'applique aux deux instances Nextcloud (`nextcloud` =
> `old-nextcloud.etsmtl.club` et `nextcloud-new` = `nextcloud.etsmtl.club`) en
> adaptant le namespace.

For a PHP security maintenance, the PHP site overlays:

- replace their `HTTPProxy` routes with a `requestRedirectPolicy` to
  `https://maintenance.etsmtl.club` (HTTP 302);
- scale the PHP `Deployment` to `0`;
- suspend the PHP `CronJob`s (Matomo archiving and Nextcloud cron/maintenance);
- replace the Nextcloud `PostSync` setup job command with a no-op so it does not
  try to `kubectl exec` into a scaled-to-zero deployment.

The database/Redis/PVC resources are left untouched.

## Restore

Revert the maintenance commit/PR. Argo CD will restore the original
`HTTPProxy` routes, replica counts and CronJob state on the next sync.

If a sync is not enough, check:

```bash
kubectl -n <namespace> get httpproxy,deploy,cronjob
kubectl -n <namespace> rollout status deploy/<deployment>
```
