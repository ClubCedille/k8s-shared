# Analyse de faisabilité — tiering Ceph/Garage pour le stockage Nextcloud

Date : 2026-09-04

## Résumé

C'est **techniquement faisable et déjà à moitié testé** (un bucket de test existe depuis le 2026-06-17), mais ça implique une **troisième migration** de tout le contenu Nextcloud (CephFS → Garage → Ceph RGW-avec-tier-froid-Garage), et le bénéfice réel dépend de ce qu'on cherche vraiment : performance, coût, ou résilience. Sur ce dernier point — le vrai problème aujourd'hui, c'est que **Garage est un nœud unique sans redondance** — le tiering Ceph n'est pas le bon outil.

## État actuel des deux systèmes

### Garage (nas01, 10.0.21.50)
- **1 seul nœud**, `replication_factor = 1` → **aucune redondance**. Une panne de disque ou de la machine = perte de données définitive sur les objets touchés.
- 8 disques de 10.9 TB en accès direct (pas de RAID logiciel ni matériel visible, pas de LVM) : chaque disque est un point de défaillance individuel.
- 85 TB de capacité brute, 57 TB libres (83.7%).
- Bucket `nextcloud-data` : contenu réel de la migration (~8 TB, 13 groupes de fichiers).
- **Un bucket de test `cedille-rgw-cloudtier-test` existe déjà** (créé 2026-06-17, 12.2 GiB / 8 objets) — voir ci-dessous.

### Ceph (cluster pve01-08, externe à k8s-shared via rook-ceph-external)
- 32 OSD **SSD**, 8 mons, `HEALTH_OK`, redondance multi-hôte réelle (bien plus résilient que Garage).
- 56 TiB brut, **39 TiB déjà utilisés, seulement 17 TiB disponibles** (69% plein) — capacité partagée avec les bases de données de production (CNPG) et les autres workloads du cluster.
- RGW (radosgw) déjà actif : 4 daemons, endpoint `http://10.0.21.59:7480`.
- C'est précisément ce cluster (via CephFS) qui causait les corruptions ayant motivé la migration Nextcloud vers S3 — voir [[project_cephfs_rbd_migration]]. Le risque identifié était spécifique au **client kernel CephFS** ; RGW est un chemin de code différent (accès objet, pas POSIX) et n'est pas concerné par ce bug précis.

## Ce qui existe déjà : le tiering RGW → Garage

Le zonegroup/zone RGW par défaut a **déjà** une storage class `GARAGE_COLD` configurée comme cible `cloud-s3` pointant vers Garage (`cedille-rgw-cloudtier-test`), avec :
- `allow_read_through: true` — un objet transitionné vers Garage reste lisible de façon transparente via RGW (pas besoin de restore complet avant lecture).
- `read_through_restore_days: 1`.
- `retain_head_object: true` — un stub reste côté Ceph après transition (consomme un peu d'espace même pour les objets "froids").

C'est la fonctionnalité native de Ceph RGW appelée **Cloud Transition** (lifecycle policy avec storage class externe). C'est le mécanisme standard pour ce genre de tiering — quelqu'un l'avait déjà testé à petite échelle, jamais mis en prod.

**Sens du flux :** ce mécanisme est conçu pour faire remonter les objets **chauds sur Ceph (SSD, rapide, cher)** et les redescendre automatiquement (par âge, via une règle de lifecycle) **vers Garage (HDD, lent, abondant) en froid**. C'est l'inverse de la situation actuelle où tout vit uniquement sur Garage.

## Ce qu'il faudrait faire pour l'activer sur les vraies données

1. Créer un bucket RGW réel (placement `default-placement`, storage class `STANDARD` par défaut) pour Nextcloud.
2. Migrer les ~8 TB actuellement dans `nextcloud-data` (Garage) vers ce nouveau bucket RGW — une **troisième copie complète** du même contenu qu'on vient de déplacer deux fois (CephFS → Garage, et maintenant Garage → RGW).
3. Reconfigurer `OBJECTSTORE_S3_HOST`/`PORT`/`BUCKET` de Nextcloud pour pointer vers RGW au lieu de Garage (le code Nextcloud ne change pas, c'est une simple bascule d'endpoint S3 — le tiering est entièrement transparent côté client).
4. Définir une règle de lifecycle (`aws s3api put-bucket-lifecycle-configuration` ou `radosgw-admin`) transitionnant les objets vers `GARAGE_COLD` après N jours sans accès.

## Points de friction / limites connues

- **Capacité SSD Ceph déjà tendue** (17 TiB dispo, 69% plein, partagé avec les bases de données critiques du cluster). Tant qu'un objet n'a pas été transitionné, il occupe de l'espace SSD précieux — il faudrait une politique de transition agressive (courte fenêtre "chaud") pour ne pas grignoter la capacité réservée aux workloads de prod.
- **Limitations connues du Cloud Transition RGW** : pas de support du versioning sur les objets transitionnés, contraintes sur le multipart, restore avec délai configurable (ici 1 jour) même avec read-through.
- **Ça ne règle pas le vrai problème de résilience** : les données "froides" finissent quand même sur le même nœud Garage unique, sans redondance. Le tiering déplace de la capacité, pas le risque de panne.
- **Effort de migration non-trivial** : refaire une copie complète de ~8 TB (même ordre de grandeur que la migration CephFS→Garage qu'on vient de finir), avec les mêmes types de pièges potentiels (noms de fichiers, throttling, etc.).

## Si l'objectif est la résilience (pas la performance/coût)

Si le vrai problème à régler est "Garage est un SPOF", des options plus directes et moins coûteuses en effort que le tiering Ceph existent :
- **Cluster Garage multi-nœud** : ajouter 1-2 nœuds Garage avec `replication_factor = 3` — c'est le mécanisme natif et supporté de Garage pour la redondance, sans dépendance à Ceph.
- **Sauvegarde périodique** (pas du tiering live) : copier régulièrement le contenu du bucket `nextcloud-data` vers Ceph (RGW ou CephFS/RBD) comme copie de secours froide, découplée de l'accès en lecture/écriture du quotidien. Beaucoup plus simple à opérer qu'un tiering live, et sans les limitations du Cloud Transition.

## Recommandation

Avant d'investir dans la migration vers RGW+tiering, il vaut la peine de clarifier l'objectif réel :
- **Performance** (accès plus rapide) → le tiering RGW/Garage a du sens, mais la capacité SSD dispo (17 TiB) est le facteur limitant à surveiller.
- **Coût** (libérer du Ceph SSD cher) → l'inverse de la situation actuelle (déjà tout sur Garage/HDD, donc rien à optimiser dans ce sens).
- **Résilience/DR** (le SPOF de nas01) → un cluster Garage multi-nœud ou une sauvegarde périodique vers Ceph sont des solutions plus simples et plus directement adaptées que le tiering RGW.

Le tiering Ceph/Garage existant est un outil réel et à moitié prêt, mais il répond à un problème de performance/coût, pas au problème de résilience qui semble être le plus visible aujourd'hui sur cette infra.
