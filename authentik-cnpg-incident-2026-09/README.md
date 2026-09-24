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

### 5. Restaurer la HA — PR #560 (ouverte)
`instances: 3` : les nouvelles répliques `-2`/`-3` se (re)seedent depuis le backup frais
(backup base + WAL, même timeline 17) et rejoignent proprement le quorum.

## Enseignements / Action à retenir

- **CNPG ne peut PAS rétrécir le stockage.** Toute baisse d'`walStorage` nécessite de
  reconstruire les PVC : soit failover + suppression du PVC du primaire puis changement de
  spec, soit scale à `instances: 0` / restore-migration. À mettre au backlog (30Gi → 6Gi).
- **Backups** : la méthode sélectionnée est `plugin` (pas `barmanObjectStore`); garder
  `ScheduledBackup` / les éventuels `Backup` manuels cohérents.
- **Redémarrer l'opérateur CNPG** : vérifier d'abord que tous les pods plugins sont
  `Running`, sinon on se retrouve dans le wedge "unknown plugin".
- **HA non testée en réel** : #560 doit être validé en observant l'état des répliques et
  un failover éventuel avant de le considérer acquis.
- **CI (bruit pré-existant)** : `kube-score` (kubernetes-repo-standards) échoue sur `main`
  indépendamment de ces PRs; `kubeconform` utilise un schéma datree obsolète qui rejette
  `deleteDataOnScaleDown` (raison de la clôture de #559). Voir à corriger les schémas.

## Références

- PRs : #558 (wal 30Gi, merged), #559 (deleteDataOnScaleDown, closed), #560 (HA, ouvert).
- Backup valide : `postgresql-authentik-manual-20260924b` (ns `authentik`, `method: plugin`).
- Objets k8s : `apps/authentik/resources/postgresql.yaml`, `deploy/cloudnative-pg`
  + `deploy/barman-cloud` + `svc/barman-cloud` (ns `cnpg-system`).