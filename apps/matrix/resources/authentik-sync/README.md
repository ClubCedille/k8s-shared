# Authentik → Matrix Space Sync

Synchronise automatiquement les membres de groupes Authentik vers des Spaces et salons privés Matrix via l'API Admin de Synapse.

## Ressources

- `authentik-sync-configmap.yaml` : ConfigMap `authentik-sync-config` contenant le script `sync.py` et `mapping.json` (association `groupe_authentik -> [space_id, room_ids]`).
- `authentik-sync-cronjob.yaml` : `CronJob` `authentik-space-sync` exécuté toutes les 10 minutes (`*/10 * * * *`).

## Configuration requise

### 1. Secret manuel `authentik-sync-secret`

À créer dans le namespace `matrix` avec :
- `authentik-token` : token API Authentik (utilisateur de service ou admin en lecture sur `/api/v3/core/users/`).
- `synapse-admin-token` : access token d'un compte Matrix admin (pour appeler `/_synapse/admin/v1/join/...`).

```sh
kubectl -n matrix create secret generic authentik-sync-secret \
  --from-literal=authentik-token="<TOKEN_AUTHENTIK>" \
  --from-literal=synapse-admin-token="<TOKEN_ADMIN_SYNAPSE>"
```

### 2. Mapping dans `mapping.json`

Dans `authentik-sync-configmap.yaml`, renseigne les IDs des Spaces/salons (trouvables dans Cinny : *Paramètres → Avancé → Room ID*) pour chaque groupe Authentik :

```json
{
  "kick_removed": false,
  "groups": {
    "mon-groupe-authentik": [
      "!spaceId:matrix.etsmtl.club",
      "!roomId:matrix.etsmtl.club"
    ]
  },
  "admins": {
    "exec": [
      "!spaceGeneralId:matrix.etsmtl.club"
    ]
  }
}
```

Passe `"kick_removed": true` une fois le mapping validé si tu veux aussi retirer automatiquement les utilisateurs qui quittent un groupe Authentik.

*(Note : pour la section `admins`, le compte `svc_sync` doit lui-même avoir le Power Level `100` dans le Space/salon concerné.)*

## Test manuel

```sh
kubectl -n matrix create job --from=cronjob/authentik-space-sync test-sync
kubectl -n matrix logs job/test-sync -f
```
