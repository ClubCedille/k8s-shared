# Nextcloud Ceph RGW hot tier / Garage cold tier runbook

Nextcloud's primary S3 storage (`OBJECTSTORE_S3_*` in `helm/nextcloud-values.yaml`)
points at Ceph RGW (`10.0.21.59:7480`), not GarageHQ directly. The bucket is
provisioned via `resources/objectbucketclaim.yaml` (same pattern as
`distro-mirror`/`loki`/`mimir`), and `resources/bucket-setup-job.yaml` (ArgoCD
`PostSync` hook) applies a lifecycle policy transitioning objects older than
1 day to the `GARAGE_COLD` storage class, which physically stores them on
GarageHQ. Reads of transitioned objects are proxied transparently by RGW
(`allow_read_through`) — Nextcloud has no awareness of the tiering.

See `nextcloud-migration-2026-09/analyse-tiering-ceph-garage.md` (repo root)
for the full feasibility analysis and rationale, and
`apps/distro-mirror/docs/lifecycle-runbook.md` for background on `GARAGE_COLD`
itself (pre-existing zone placement target, shared across apps — not created
by this app).

## Why 1 day, not 1 hour

Standard S3 lifecycle `<Days>` granularity is whole days — there is no
supported per-bucket sub-day transition in RGW. The only way to get shorter
transitions is `rgw_lc_debug_interval`, a **global RGW daemon** debug setting
explicitly documented as "do not modify for a production cluster" — it would
also warp the lifecycle timing of unrelated buckets (`distro-mirror`, Mimir/Loki
chunk buckets). Decided against it (2026-09-04); 1 day is the practical
minimum given real usage volume is well under the ~17 TiB free on the Ceph
SSD pool.

## Migration from the old Nextcloud instance

This bucket is filled by a fresh rclone sync from the **original** Nextcloud
instance (CephFS-backed, `nextcloud` namespace) — not by re-copying the
Garage-only `nextcloud-data` bucket (10.0.21.50:3900), which is kept
untouched as a benchmarking reference. See
`nextcloud-migration-2026-09/` (repo root) for the migration tooling
(rclone pod pattern, S3-incompatible filename rename script) reused from the
first migration pass.

## Verifying the tiering

```bash
# on any RGW host, e.g. ssh root@10.0.21.51 (or any pve0X mon host)
radosgw-admin zonegroup placement list   # confirm GARAGE_COLD present
radosgw-admin lc list                    # lifecycle processing status
radosgw-admin lc process --bucket <bucket-name>   # force a pass
radosgw-admin bucket stats --bucket <bucket-name>
```

Lifecycle processing runs on RGW's own daily schedule by default — even at
1 day, don't expect to observe a transition sooner than ~24-48h passively.
