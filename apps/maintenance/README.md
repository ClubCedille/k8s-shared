# Maintenance page

Static nginx page served at <https://maintenance.etsmtl.club>. It does not run
PHP.

## Security maintenance procedure

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
