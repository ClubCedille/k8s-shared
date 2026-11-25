# Restauration de la base Postgres Grafana (CNPG) — runbook

Contexte : migration du chart Grafana `10.5.15` → `14.5.0` (Grafana 12.3.1 → 13.3.1,
repo `grafana.github.io/helm-charts` → `grafana-community.github.io/helm-charts`).

Grafana 13 migre automatiquement les dashboards/folders des tables SQL legacy vers
l'**unified storage** au démarrage (migration one-shot, tracée dans la table
`unifiedstorage_migration_log`). Cette migration est sans retour : si elle tourne
et que le résultat est incorrect, la seule voie de rollback est de restaurer la
base **d'avant la migration** et de redémarrer sur cette base.

Ce document décrit comment restaurer la base `grafana` du cluster CNPG
`postgresql-grafana` (namespace `monitoring`).

---

## 1. Points de reprise disponibles (16–17 nov. 2026)

| # | Type | Détail |
|---|------|--------|
| A | Backup CNPG on-demand | `Backup/postgresql-grafana-pre-grafana13-20261117` (namespace `monitoring`), terminé le 2026-11-17T18:57:06Z, méthode `plugin` (barman-cloud 0.5.0), timeline 7, ObjectStore `cnpg-grafana-b2` (Backblaze B2, `s3://k8s-shared-bucket/postgresql-grafana`) |
| B | Dump logique (`pg_dump -Fc`) | `/home/louis/backups/grafana-20261117.dump` — 287 711 octets, format CUSTOM, PostgreSQL 17.2 → 671 entrées TOC, base `grafana` entière. sha256 `d8ff0c0b1a17f76a8f545fb46dedfa01c461cbfbc167f96fd0d826f9bb1bdf9a`. Liste du contenu : `/home/louis/backups/grafana-20261117.list` |
| C | Backups CNPG planifiés | `cnpg-backup-schedule-*`, un par jour à 06:40, rétention 30 jours (voir `kubectl get backups -n monitoring`) |

Les deux backups A et B ont été vérifiés le 2026-11-17 (TOC du dump lisible via
`pg_restore --list`, phase `completed` sur le Backup CNPG).

> ⚠️ `/home/louis/backups/` vit sur le poste de Laurent/Louis (machine locale).
> Copier `grafana-20261117.dump` ailleurs (poste, stockage chiffré) si on veut
> s'en servir en cas de perte du poste. Ne **jamais** committer ce fichier dans git.

## 2. Prérequis

- Accès `kubectl` au cluster (`current-context` = `cedille-k8s-shared`), droits sur `monitoring`.
- Accès en lecture à l'ObjectStore B2 (les credentials `b2-creds` sont déjà dans le cluster et réutilisés via le plugin — aucune manipulation manuelle des secrets n'est nécessaire).
- Décider AVANT d'agir : restauration dans un **nouveau cluster** (option A1, recommandée) ou **overwrite** du cluster existant (option A2, plus rapide mais destructive).

## 3. Option A — Restauration via barman-cloud / Backblaze B2 (recommandée)

### A1. Restaurer dans un nouveau cluster (sûr, non destructif)

1. **Lister les backups disponibles** et noter celui à utiliser :
   ```bash
   kubectl get backups -n monitoring --sort-by=.metadata.creationTimestamp
   ```

2. **Créer le cluster de restauration** (manifest) :
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: postgresql-grafana-restore
     namespace: monitoring
   spec:
     instances: 3
     imageName: ghcr.io/cloudnative-pg/postgresql:17.2
     bootstrap:
       recovery:
         source: source
         # Point-in-time recovery optionnel (décommenter + ajuster) :
         # recoveryTarget:
         #   targetTime: "2026-11-17T18:57:00Z"   # ISO-8601 UTC
         # ou recoveryTarget: { backupID: "<nom-du-backup>" }
     externalClusters:
       - name: source
         plugin:
           name: barman-cloud.cloudnative-pg.io
           parameters:
             barmanObjectName: cnpg-grafana-b2
             serverName: postgresql-grafana   # nom du cluster d'origine tel qu'archivé dans B2
     storage:
       size: 5Gi
       storageClass: ceph-rbd
     # Ré-archivage WAL du cluster restauré (serverName par défaut = nom du nouveau cluster,
     # donc aucune écrasement de l'archive existante) :
     plugins:
       - name: barman-cloud.cloudnative-pg.io
         isWALArchiver: true
         parameters:
           barmanObjectName: cnpg-grafana-b2
   ```
   ```bash
   kubectl apply -f postgresql-grafana-restore.yaml
   kubectl get cluster postgresql-grafana-restore -n monitoring -w
   ```

3. **Vérifier** le cluster restauré :
   ```bash
   kubectl exec -n monitoring postgresql-grafana-restore-1 -- \
     psql -U postgres -d grafana -c '\dt' | head -30
   kubectl exec -n monitoring postgresql-grafana-restore-1 -- \
     psql -U postgres -d grafana -c 'select count(*) from dashboard; select count(*) from "user";'
   ```
   (Si Grafana 13 avait déjà migré vers l'unified storage, vérifier aussi `unifiedstorage_migration_log`.)

4. **Basculer Grafana** sur la base restaurée : le repo est la source de vérité (ArgoCD `selfHeal`), donc passer par git :
   ```yaml
   # apps/grafana/helm/values.yaml
   env:
     GF_DATABASE_HOST: postgresql-grafana-restore-rw.monitoring.svc.cluster.local:5432
   ```
   PR → merge → ArgoCD redéploie Grafana. Vérifier `/api/health`, le login Authentik et les dashboards.

5. **Après validation** : supprimer l'ancien cluster `postgresql-grafana` (et ses PVCs) **uniquement** une fois le nouveau validé, ou le garder tel quel pour retour arrière. Si on veut revenir au nom d'origine, mettre à jour `GF_DATABASE_HOST` dans values.yaml en conséquence (PR).

### A2. Restauration « en place » (même nom, service inchangé) — destructive

À n'envisager que si A1 est trop lent et que les backups A+B sont vérifiés :

1. Suspendre l'auto-heal de l'app Grafana (sinon ArgoCD remettra `replicas: 1` en permanence) :
   ```bash
   argocd app set grafana --self-heal false   # ou éditer l'Application dans l'UI
   kubectl scale deploy grafana -n monitoring --replicas=0
   ```
2. Supprimer le cluster CNPG (⚠️ détruit les données courantes — c'est le but, elles sont backupées) :
   ```bash
   kubectl delete cluster postgresql-grafana -n monitoring
   # vérifier / supprimer les PVC orphelins si présents :
   kubectl get pvc -n monitoring | grep postgresql-grafana
   ```
3. Recréer le cluster avec le **même nom** et un bootstrap recovery :
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: postgresql-grafana          # ← même nom, les Services -rw/-ro suivent
     namespace: monitoring
   spec:
     instances: 3
     imageName: ghcr.io/cloudnative-pg/postgresql:17.2
     bootstrap:
       recovery:
         source: source
         # recoveryTarget:
         #   targetTime: "2026-11-17T18:57:00Z"
     externalClusters:
       - name: source
         plugin:
           name: barman-cloud.cloudnative-pg.io
           parameters:
             barmanObjectName: cnpg-grafana-b2
             serverName: postgresql-grafana
     storage:
       size: 5Gi
       storageClass: ceph-rbd
     plugins:
       - name: barman-cloud.cloudnative-pg.io
         isWALArchiver: true
         parameters:
           barmanObjectName: cnpg-grafana-b2
   ```
   `GF_DATABASE_HOST` reste `postgresql-grafana-rw.monitoring.svc.cluster.local:5432` — rien à changer dans le repo.
4. Réactiver l'auto-heal + rescaler :
   ```bash
   argocd app set grafana --self-heal true
   kubectl scale deploy grafana -n monitoring --replicas=1
   ```

## 4. Option B — Restauration logique via `pg_dump` (fallback)

Plus simple, mais écrase la base courante : à réserver si barman est indisponible.

1. Suspendre l'auto-heal ArgoCD + passer Grafana à 0 replica (voir A2, étape 1).
2. Recréer la base (dans le pod primaire, auth locale `trust` en socket unix) :
   ```bash
   kubectl exec -n monitoring postgresql-grafana-1 -- \
     psql -U postgres -d postgres -c 'DROP DATABASE grafana;' \
                                  -c 'CREATE DATABASE grafana OWNER grafana;'
   ```
   > ⚠️ Destructif. Ne pas faire sans le backup CNPG (A ou C) vérifié.
3. Restaurer le dump :
   ```bash
   kubectl exec -i -n monitoring postgresql-grafana-1 -- \
     pg_restore -U postgres -d grafana --no-owner --role=grafana \
     < /home/louis/backups/grafana-20261117.dump
   ```
4. Réactiver self-heal ArgoCD, rescaler Grafana à 1, vérifier (§5).

## 5. Vérifications post-restauration

- [ ] `kubectl get cluster -n monitoring` → `Cluster in healthy state`
- [ ] `kubectl logs -n monitoring deploy/grafana` sans erreur de migration ; attention aux lignes `unified_storage` / `migration`
- [ ] `curl -s https://grafana.etsmtl.club/api/health` → `{"database": "ok", ...}`
- [ ] Login Authentik OIDC OK (compte admin / groupe `grafana-dashboard-creators`)
- [ ] Dashboards Mimir/Loki se chargent ; datasources provisionnés intacts
- [ ] Dashboard créé via l'UI avant restore encore visible (présent dans la table legacy `dashboard` avant migration 13)
- [ ] Alertes/notification policies : vérifier `kubectl exec ... psql -c '\dt'` si doute
- [ ] ArgoCD : app `grafana` Synced/Healthy

## 6. Pièges connus

- **Ne jamais ré-appliquer le manifest ArgoCD pendant une restauration** : le repo est la source de vérité, toute action manuelle sera écrasée (ou inversement ré-écrase la restauration). Suspendre `selfHeal` d'abord.
- **La migration unified storage de Grafana 13 est one-shot** : après restauration d'un backup d'avant migration, Grafana 13 relancera la migration au démarrage — c'est le comportement attendu. Si on doit revenir à Grafana 12.x, restaurer, puis re-pinner le chart `10.5.15` avant de redémarrer Grafana.
- **Rollback après migration** : Grafana 13 écrit dans unified storage ; les tables legacy deviennent obsolètes. Restaurer un backup pré-migration est alors la **seule** voie de rollback.
- **Le segment de backup `2026-10-23` a échoué** (`cnpg-backup-schedule-20261023064000`) — sans impact ici, le backup du jour est `completed`.
- Rétention B2 : 30 jours (`retentionPolicy` de l'ObjectStore `cnpg-grafana-b2`).
