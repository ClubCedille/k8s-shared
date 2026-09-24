# Incident CNPG — Authentik (2026-09-24)

Downstream effect: `auth.etsmtl.club` intermittently unavailable / 503; ArgoCD App
`authentik` stuck `OutOfSync`; CNPG replicas `postgresql-authentik-2`/`-3` crash-looping.

## Symptômes

- ArgoCD app `authentik` bloque en sync : le webhook d'admission refuse le cluster —
  `spec.walStorage` ne peut pas rétrécir (`can't shrink`).
- Pods répliques `postgresql-authentik-2` / `-3` en `CrashLoopBackOff` (tentatives de
  restore sur un backup obsolète, timelines 17/18 incohérentes).
- Après redémarrages de l'opérateur CNPG : `Cluster cannot proceed to reconciliation due
  to an unknown plugin being required`.
- Ouvrirage authentik (web) en crash-loop pendant la fenêtre de maintenance des instances.

## Causes racines (empilées)

1. **Dérive de stockage (le déclencheur principal).**
   Git déclarait `walStorage: 6Gi`, mais les PVC réels étaient a `30Gi` (`-2-wal`),
   `26Gi` (`-1-wal`, `-3-wal`). CNPG **ne rétrécit jamais le stockage** : le webhook de
   admission rejette toute spec dont `walStorage` est inférieur à la taille des PVC
   existants → ArgoCD bloqué.
2. **Réconcile opérateur court-circuitée.**
   Même quand on montait la spec (`26Gi`), l'opérateur plantait l'ensemble de la
   réconcile sur `cannot decrease storage requirement from=30Gi to=26Gi
   pvcName=postgresql-authentik-2-wal` **avant** la logique de scale-down → les répliques
   casses ne pouvaient pas être décommissionnées proprement.
3. **Répliques irrécupérables (toute seule, failover).**
   Les répliques tentaient un restore PITR depuis un backup de base obsolète produisant un
   PGDATA invalide (écart de timeline 17 vs 18, `pg_controldata` en erreur). Boucle
   attach/recreate du PVC.
4. **Latch plugin corrompu.**
   Après redémarrages de `deploy/cloudnative-pg`, l'opérateur refusait toute réconcile
   ("unknown plugin"): le pod plugin `barman-cloud` (port 9090) retombait pendant la
   fenêtre de démarrage, et la découverte du plugin se fait via le Service `barman-cloud`
   (`cnpg.io/pluginName`, ns `cnpg-system`).
5. **Archive barman contaminée (fork timeline 18).**
   Pendant l'incident, un fork orphelin **timeline 18** (à LSN `6F/490A7320`) a été
   archivé dans B2. Chaque nouvelle réplique (basebackup sur timeline 17) replaît le WAL
   de l'archive, tombe sur le segment/timeline 18 et échoue :
   `requested timeline 18 is not a child of this server's history` → CrashLoopBackOff en
   boucle. Les logs "Checking for free disk space for WALs..." ne sont PAS un manque
   d'espace : c'est le garde-fou CNPG exécuté à chaque start/stop (volume 30Gi, ~560 MiB
   utilisés) ; le vrai blocage est le replay de ce fork mort.

## Résolution

### 1. Déclarer la seule taille cohérente en Git — PR #558 (merged)
`walStorage: 30Gi` (= PVC le plus grand en vie), `instances: 1`.
→ le webhook laisse passer, ArgoCD redevient `Synced`, la réconcile opérateur n'est plus
abortée par le contrôle de shrink.

### 2. Débloquer l'opérateur (clearing du latch plugin)
Attendre que le pod plugin `barman-cloud` soit `Running`, puis :
```bash
kubectl -n cnpg-system rollout restart deploy/cloudnative-pg   # 3e fois: réconcile passe
kubectl -n authentik get cluster postgresql-authentik          # phase -> Waiting for the instances to become active
```

### 3. Backup cohérent (méthode plugin)
Le cluster utilise barman-cloud **en plugin** (`spec.plugins.barman-cloud.cloudnative-pg.io`,
`barmanObjectName: cnpg-authentik-b2`). La méthode legacy `barmanObjectStore` échoue
("cluster has no backup section"). Backup manuel valide :
```bash
kubectl -n authentik create -f - <<'EOF'
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: postgresql-authentik-manual-20260924b
  namespace: authentik
spec:
  cluster:
    name: postgresql-authentik
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
# phase=completed (timeline du primaire: 17)
```

### 4. Éliminer les répliques cassées (méthode documentée CNPG)
Référence : https://cloudnative-pg.io/documentation/1.20/failure_modes/
CNPG ne re-réutilise PAS un PVC supprimé avant le pod : pour enlever définitivement une
instance, supprimer la paire **PVC + pod** ensemble. Faits ici (déjà `instances: 1`, donc l'opérateur ne recrée pas les répliques) :
```bash
kubectl -n authentik delete \
  pvc/postgresql-authentik-2 pvc/postgresql-authentik-2-wal \
  pvc/postgresql-authentik-3 pvc/postgresql-authentik-3-wal \
  pod/postgresql-authentik-2 pod/postgresql-authentik-3
```
Résultat : une seule instance saine (`postgresql-authentik-1`, data 10Gi + wal 30Gi, PG16
OK, authentik accessible).

> Le pod primaire `-1` est ensuite bref `Terminating` / `Init` : c'est l'opérateur qui
> applique la croissance du PVC wal 26Gi → 30Gi (restart sans switchover). Normal.

### 5. Purger le fork timeline 18 de l'archive barman
L'archive (B2, endpoint `https://s3.ca-east-006.backblazeb2.com`, path `s3://k8s-shared-bucket/postgresql-authentik`, chart barman: `wals/<tli><lsn>/<fichier>.gz`) contenait 2 objets timeline 18 (`0x12`) :
```text
postgresql-authentik/postgresql-authentik/wals/00000012.history.gz
postgresql-authentik/postgresql-authentik/wals/000000120000006F00000049.gz
postgresql-authentik/postgresql-authentik/wals/000000120000006F/000000120000006F00000049.gz  # doublon dossier
```
Supprimés via un pod jetable (`ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.5.0`, boto3, creds du secret `b2-creds`). Nettoyage ensuite du pod et des PVC de la réplique bloquée (`-4` puis `-5`), cf. note POD Security : le webhook du namespace retire `env`/`envFrom` → injecter les identifiants en dur dans le script du pod jetable.

### 6. Restaurer la HA — PR #560 (merged)
`instances: 3`. Avec l'archive propre, les nouvelles répliques (basebackup du primaire,
timeline 17, replay depuis l'archive) rejoignent le quorum. État final : 3/3 instances
Ready, `Ready=True`, `ContinuousArchiving=True`, ArgoCD `Healthy`, lag de réplication 0.

## Enseignements / Action à retenir

- **CNPG ne peut PAS rétrécir le stockage.** Toute baisse d'`walStorage` nécessite de
  reconstruire les PVC : soit failover + suppression du PVC du primaire puis changement de
  spec, soit scale à `instances: 0` / restore-migration. À mettre au backlog (30Gi → 6Gi).
  Coût réel mesuré : `pg_wal` ~560 MiB, production ~26 Mo/jour → 2Gi serait confortable.
- **Backups** : la méthode sélectionnée est `plugin` (pas `barmanObjectStore`); garder
  `ScheduledBackup` / les éventuels `Backup` manuels cohérents. Layout barman: `base/` +
  `wals/<tli><lsn>/`. La purge d'un fork mort se fait par `delete_object` (B2/S3) sur les
  `.history.gz` et segments du timeline concerné.
- **Redémarrer l'opérateur CNPG** : vérifier d'abord que tous les pods plugins sont
  `Running`, sinon on se retrouve dans le wedge "unknown plugin".
- **"insufficient / free disk space for WALs"** = garde-fou CNPG (start/stop), pas un
  manque d'espace : regarder la timeline du replay plutôt que l'espace disque.
- **HA restaurée + testée** : 3/3 ready, lag 0, ArgoCD Healthy. Un failover réel reste à
  tester un de ces jours.
- **CI (bruit pré-existant)** : `kube-score` (kubernetes-repo-standards) échoue sur `main`
  indépendamment de ces PRs; `kubeconform` utilise un schéma datree obsolète qui rejette
  `deleteDataOnScaleDown` (raison de la clôture de #559). Voir à corriger les schémas.

## Références

- PRs : #558 (wal 30Gi, merged), #559 (deleteDataOnScaleDown, closed), #560 (HA 3 instances, merged), #561 (ce post-mortem).
- Backup valide : `postgresql-authentik-manual-20260924b` (ns `authentik`, `method: plugin`).
- Objets k8s : `apps/authentik/resources/postgresql.yaml`, `deploy/cloudnative-pg`
  + `deploy/barman-cloud` + `svc/barman-cloud` (ns `cnpg-system`).