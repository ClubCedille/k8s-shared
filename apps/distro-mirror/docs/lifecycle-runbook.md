# distro-mirror bucket setup runbook

Two S3-API-level settings apply automatically via the `distro-mirror-bucket-setup`
Job (an ArgoCD `PostSync` hook, `resources/bucket-setup-job.yaml`): the
anonymous public-read policy and the GARAGE_COLD lifecycle transition. This
document is the manual-verification companion, not a deploy step.

## GARAGE_COLD cold-tier

`GARAGE_COLD` is a pre-existing RGW zone placement target used by other apps
(Nextcloud, Supabase) — it is **not** created by this app, only referenced.
Confirmed present on the external Ceph cluster via (run on any RGW node,
e.g. `ssh root@10.0.21.51`, IP is the pve01 host used for the external Ceph
cluster):

```bash
radosgw-admin zonegroup placement list
radosgw-admin zone placement list
```

Expected: `storage_classes` includes both `STANDARD` and `GARAGE_COLD`, and
`GARAGE_COLD`'s `tier_targets` entry is a `cloud-s3` tier pointing at
`http://10.0.21.50:3900` (GarageHQ), target bucket `cedille-rgw-cloudtier-test`,
with `allow_read_through: true` and `read_through_restore_days: 1` (reading a
cold-tiered object restores it to hot storage for at least a day).

## What the setup Job does

1. `s3api put-bucket-policy` — anonymous `s3:GetObject` on `arn:aws:s3:::<bucket>/*`,
   required since the mirror is public/unauthenticated.
2. `s3api put-bucket-lifecycle-configuration` — transitions all objects to
   `GARAGE_COLD` after 7 days. This is a coarse safety net; the real
   "keep only supported versions" retention lives in the sync CronJobs'
   `--include` globs, which stop re-syncing (and should eventually prune)
   files for EOL releases — age alone doesn't mean "unsupported." A short
   window means most ISO/cloud-image traffic will actually be served from
   Garage rather than hot Ceph storage; revisit if that ends up hurting
   download performance for recently-synced files.

Both calls are idempotent (`put-*` overwrites, no create-if-missing
ambiguity) so the Job re-runs safely on every ArgoCD sync.

## Verifying a transition manually

Lifecycle processing runs on RGW's own schedule (not immediate — daily by
default), so even at 7 days a real transition can take over a week to
observe passively. To force and observe it sooner on a test object, on an
RGW node:

```bash
radosgw-admin lc list
radosgw-admin lc process --bucket <bucket-name>
radosgw-admin bucket stats --bucket <bucket-name>
```
