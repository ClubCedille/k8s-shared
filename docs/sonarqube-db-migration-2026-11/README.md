# Migration DB SonarQube — novembre 2026

Procédure de mise à jour de SonarQube Community Build de 26.9 vers **26.10**, avec migration du schéma PostgreSQL. Contexte : la DB était restée au schéma `202603003` (26.3) alors que l'image tournait en 26.9, ce qui mettait l'instance en `DB_MIGRATION_NEEDED` et bloquait le Job Helm `change-admin-password-hook` depuis le 14/11.

## État initial (26/11/2026)

| Élément | Valeur observée |
|---|---|
| Image déployée | `sonarqube:26.9.0.129388-community` |
| Schéma DB (`schema_migrations`) | `202603003` (26.3) |
| `/api/system/status` | `DB_MIGRATION_NEEDED` |
| Extension custom | `sonarqube-community-branch-plugin` **26.5.0** (non compatible avec 26.9) |
| Chart Helm | `2026.5.1006` (distant : `2026.5.1007`) |
| Backup | `backupId 20261126T012827`, phase `completed`, B2 `s3://k8s-shared-bucket/postgresql-sonarqube` |

## Compatibilités à respecter

- **Chemin de mise à jour** : SonarSource autorise un saut direct entre versions d'une même année. `26.3 → 26.10` est donc valide (pas d'étape intermédiaire 25.12/26.1 nécessaire).
- **Plugin community-branch** : la règle amont est `major.minor du plugin == version de SonarQube`. Le plugin 26.10.0 annonce explicitement le support de SonarQube 26.10. C'est le dernier couple compatible : l'image `26.11.0.134175-community` existe mais aucun plugin 26.11 n'est publié.
- Le chart `2026.5.1008` a encore `community.buildNumber: 26.9.0.129388` par défaut → il faut le forcer à `26.10.0.133078` dans `values.yaml`.
- L'ephemeral-storage passe de `512000M` (défaut amont) à `1Gi` request/limit : les données, logs et index sont sur le PVC `sonarqube-sonarqube` (20Gi), et l'usage ephemeral mesuré est d'environ 33 Mi (emptyDir `webapp`).

Les changements sont dans la PR [#801](https://github.com/ClubCedille/k8s-shared/pull/801) (commit `77301a3`).

## Procédure

### 1. Backup (fait le 26/11, à refaire si la DB a bougé depuis)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: sonarqube-pre-migration-YYYYMMDD
  namespace: sonarqube
spec:
  cluster:
    name: postgresql-sonarqube-cluster
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF

kubectl get backup sonarqube-pre-migration-YYYYMMDD -n sonarqube -o jsonpath='{.status.phase}{"\n"}{.status.backupId}{"\n"}'
```

Attendre `completed` et noter le `backupId` (ici `20261126T012827`).

### 2. Déployer l'image 26.10

La PR #801 doit être approuvée par `@ClubCedille/service` puis mergée. ArgoCD (`HEAD`, auto-sync avec prune/selfHeal) déploie automatiquement. Vérifier :

```bash
kubectl get deploy sonarqube-sonarqube -n sonarqube -o jsonpath='{.spec.template.spec.containers[0].image}'
# sonarqube:26.10.0.133078-community
kubectl get pods -n sonarqube -l app=sonarqube -w
```

Le pod peut rester en `DB_MIGRATION_NEEDED` : c'est attendu, la migration n'est pas encore lancée.

### 3. Vérifier l'état avant migration

```bash
curl -s https://sonarqube.etsmtl.club/api/system/status
# {"version":"26.10.0.133078","status":"DB_MIGRATION_NEEDED"}
```

Le mot de passe admin est dans le secret `sonarqube-secrets` (clés `password` / `currentPassword`). Ne pas l'afficher dans les logs.

### 4. Déclencher la migration

La documentation SonarSource décrit l'UI `https://sonarqube.etsmtl.club/setup` (bouton *Upgrade*). Le webapp appelle en interne :

```
POST /api/system/migrate_db
```

Équivalent curl (authentification admin requise) :

```bash
PASS=$(kubectl get secret sonarqube-secrets -n sonarqube -o jsonpath='{.data.password}' | base64 -d)
curl -sS -u "admin:$PASS" -X POST https://sonarqube.etsmtl.club/api/system/migrate_db
```

Si l'authentification échoue, réessayer avec la clé `currentPassword` (le hook de changement de mot de passe n'a jamais abouti). Le `/setup` de l'UI reste la méthode supportée en dernier recours.

### 5. Suivi et vérifications

```bash
# boucler jusqu'à "status":"UP"
curl -s https://sonarqube.etsmtl.club/api/system/status

# logs de migration
kubectl logs -n sonarqube -l app=sonarqube --tail=200 | grep -i -E 'migration|upgrad|ERROR'

# schéma DB (devrait contenir 202610xxx)
P=$(kubectl get secret postgres-secret-sonarqube -n sonarqube -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n sonarqube postgresql-sonarqube-cluster-1 -- \
  sh -c "PGPASSWORD='$P' psql -h 127.0.0.1 -U sonarqube -d sonarqube -tAc \
  'select version from schema_migrations order by version desc limit 5;'"
```

Une fois le status `UP` :

- le plugin `26.10.0` est chargé (javaagent `web` + `ce`) et la webapp patchée est servie depuis l'emptyDir `/opt/sonarqube/web` ;
- le Job `sonarqube-sonarqube-change-admin-password-hook` doit se terminer et être supprimé (`hook-delete-policy: hook-succeeded`). S'il reste bloqué, le supprimer manuellement ;
- vérifier l'API `/api/plugins/installed` ou l'UI *Administration > Marketplace* ;
- reanalyser les projets (recommandation SonarSource post-update).

## Exécution du 26/11/2026

| Heure (UTC) | Événement |
|---|---|
| 01:28 | Backup CNPG terminé (`backupId 20261126T012827`) |
| 01:35 | PR #801 mergée ; ArgoCD déploie image `26.10.0.133078-community`, chart `2026.5.1008`, `ephemeral-storage: 1Gi` |
| 01:38 | `POST /api/system/migrate_db` → `{"state":"MIGRATION_RUNNING"}`, puis `DB_MIGRATION_RUNNING` |
| ~01:45 | Migration DB terminée : `schema_migrations` passe de `202603003` à `202606006` ; redémarrage du web server et réindexation Elasticsearch |
| 01:54 | `/api/system/status` passe en `UP` ; le plugin `26.10.0` est chargé (`Loaded core extensions: Community Branch Plugin`) |
| 01:55–02:07 | Le pod est tué à plusieurs reprises par les probes du chart pendant la réindexation (`startupProbe`: 24×10s avec timeout 1s ; `livenessProbe` dès 60s) |

Correctif appliqué : assouplissement des probes dans `values.yaml` (`startupProbe.failureThreshold: 90`, `timeoutSeconds: 5`, `livenessProbe.initialDelaySeconds: 180`, `failureThreshold: 12`, `timeoutSeconds: 10`). Le `selfHeal` d'ArgoCD a été désactivé temporairement pendant l'application du correctif en live, puis réactivé après merge de la PR de correction.

Le Job `change-admin-password-hook` (bloqué depuis le 14/11 sur `DB_MIGRATION_NEEDED`) s'est terminé normalement dès le retour à `UP`.

État final après correction : pod **`1/1 Running`, 0 restart**, `curl https://sonarqube.etsmtl.club/api/system/status` → `{"version":"26.10.0.133078","status":"UP"}`, schéma DB `202606006`.

## Rollback

La migration de schéma n'est pas réversible en place. En cas d'échec :

1. Ne pas redémarrer SonarQube en boucle.
2. Restaurer la DB depuis le backup `20261126T012827` (Barman/ObjectStore `cnpg-sonarqube-b2`) dans un cluster CNPG de test ou via la procédure de restore CloudNativePG, puis repointer `jdbcOverwrite.jdbcUrl` dans `values.yaml`.
3. Revenir à l'image précédente (`26.9.0.129388-community`) et au plugin `26.5.0` si nécessaire.

## Pièges rencontrés

- Les nombreux objets `Backup` avec `spec.cluster.name: sonarqube-postgresql` (ancien nom) restent en `Unknown`/`failed` et polluent les events. Le `ScheduledBackup` actuel utilise le bon nom `postgresql-sonarqube-cluster` et produit des backups `completed` quotidiennement.
- Le défaut `ephemeral-storage: 512000M` du chart est un héritage de l'époque où `persistence.enabled: false` ; avec le PVC 20Gi il n'a aucun sens et faussait les inventaires (~1 To sur 2 pods).
- Les probes par défaut du chart ne survivent pas à une migration DB : la réindexation Elasticsearch depuis la DB peut dépasser 4 minutes sur CephFS, ce qui déclenche `startupProbe` (24×10s, timeout 1s) puis `livenessProbe`. Les valeurs assouplies dans `values.yaml` sont nécessaires pour toute future montée de version avec migration.
- L'accès via Omni (`kubectl`) a présenté des `proxy error` intermittents pendant l'opération ; le endpoint public `https://sonarqube.etsmtl.club/api/system/status` reste le moyen le plus simple de vérifier l'état.
