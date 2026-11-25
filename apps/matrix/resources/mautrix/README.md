# Mautrix Discord

Bridge Matrix ↔ Discord ([mautrix-discord](https://docs.mau.fi/bridges/go/discord/)), configuré comme application service pour Synapse.

## Ressources

- `mautrix-discord-configmap.yaml` : ConfigMap `mautrix-discord-config` contenant le modèle `config.yaml` (homeserver `http://matrix-stack-matrix-synapse:8008`, domaine `matrix.etsmtl.club`, base SQLite dans `/data/mautrix-discord.db`).
- `mautrix-discord-deployment.yaml` : Deployment `mautrix-discord` (`dock.mau.dev/mautrix/discord:v0.7.7`) avec initContainer `render-config` injectant `as-token` et `hs-token` depuis le secret `mautrix-discord-secret`.
- `mautrix-service.yaml` : Service ClusterIP `mautrix-discord` exposant le port appservice `29334`.

## Dépendances

- Secret `mautrix-discord-secret` (clés `as-token` et `hs-token`) dans le namespace `matrix`.
- PVC `mautrix-discord-pvc` défini dans [`../pvc.yaml`](../pvc.yaml).
- Route HTTPProxy éventuelle dans [`../httpproxy.yaml`](../httpproxy.yaml).
