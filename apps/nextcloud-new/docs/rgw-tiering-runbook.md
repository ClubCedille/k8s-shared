# Nextcloud — tiering Ceph RGW (chaud) / Garage (froid) — HISTORIQUE

> **Statut : clos.** Expérimentation de septembre 2026, révoquée à la suite du bug Ceph
> [tracker#80309](https://tracker.ceph.com/issues/80309) (revert #459), puis
> définitivement nettoyée le 2026-09-19 (#493) : l'`ObjectBucketClaim`
> `nextcloud-rgw-bucket` et le Job de lifecycle associé ont été supprimés du
> repo. Le bucket de test ne contenait aucune donnée unique. **Ne pas suivre les
> indications de ce document sur l'instance actuelle.**
>
> Pour l'état courant, voir `docs/nextcloud-migration-2026-09/README.md`.
> Depuis le 2026-11-23 (#719), cette instance (`nextcloud-new`) est l'instance
> autoritative, servie sur `nextcloud.etsmtl.club` ; l'ancienne instance est sur
> `old-nextcloud.etsmtl.club`.

## Ce qui avait été prévu (abandonné)

Le stockage S3 principal de Nextcloud (`OBJECTSTORE_S3_*` dans
`helm/nextcloud-values.yaml`) devait passer par Ceph RGW (`10.0.21.59:7480`),
avec un bucket provisionné via un `ObjectBucketClaim` et un Job `PostSync`
appliquant une règle de lifecycle transitionnant les objets de plus d'un jour
vers la storage class `GARAGE_COLD` (stockage physique sur GarageHQ). Les lectures
d'objets transitionnés auraient été proxifiées par RGW (`allow_read_through`),
sans que Nextcloud ait conscience du tiering.

Ce montage a été révoqué : `OBJECTSTORE_S3_*` pointe **directement** vers le bucket
GarageHQ `nextcloud-data`, et ni l'`ObjectBucketClaim` ni le Job de lifecycle
n'existent plus dans `apps/nextcloud-new/`. `GARAGE_COLD` est toujours utilisé
par d'autres apps (notamment `distro-mirror`) — voir
`apps/distro-mirror/docs/lifecycle-runbook.md`.

L'analyse de faisabilité d'origine est conservée dans
`docs/nextcloud-migration-2026-09/analyse-tiering-ceph-garage.md` (document
historique, solution non retenue).

## Décision sur la fenêtre de transition (historique)

La granularité `<Days>` des lifecycle rules S3 ne permet pas de transition sous
le jour. La seule option plus courte, `rgw_lc_debug_interval`, est un réglage
**global** du daemon RGW, explicitement déconseillé en production, qui aurait
aussi affecté les buckets d'autres apps (`distro-mirror`, Mimir/Loki). Décision
prise le 2026-09-04 : 1 jour était la valeur minimale acceptable. Cette décision
n'a plus d'objet puisque le tiering Nextcloud a été abandonné.

## Vérification générique de GARAGE_COLD

Ces commandes restent valables pour vérifier la storage class partagée, mais
**ne vérifient rien sur Nextcloud** (aucun bucket Nextcloud n'y est transitionné) :

```bash
# sur un hôte RGW, p. ex. ssh root@10.0.21.51 (hôte pve01 du cluster Ceph externe)
radosgw-admin zonegroup placement list   # confirmer la présence de GARAGE_COLD
radosgw-admin lc list                    # état du traitement des lifecycle
radosgw-admin lc process --bucket <bucket-name>   # forcer un passage
radosgw-admin bucket stats --bucket <bucket-name>
```

Le traitement des lifecycle suit le calendrier propre à RGW (quotidien par
défaut) : même avec une règle à 1 jour, ne pas s'attendre à observer une
transition passive avant ~24-48 h.
