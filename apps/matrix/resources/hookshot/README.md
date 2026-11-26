# Matrix Hookshot

Bridge d'intégrations et webhooks Matrix ([matrix-hookshot](https://matrix-org.github.io/matrix-hookshot/)), configuré comme application service pour Synapse.

## Ressources

- `matrix-hookshot-certificate.yaml` : Certificat cert-manager `hookshot-cert` (secret `hookshot-tls`) pour `hookshot.etsmtl.club`.
- `matrix-hookshot-configmap.yaml` : ConfigMap `matrix-hookshot-config` contenant `config.yml` (homeserver `http://matrix-stack-matrix-synapse:8008`, domaine `matrix.etsmtl.club`, webhooks génériques sur `:9000` avec `urlPrefix: https://hookshot.etsmtl.club/webhook`).
- `matrix-hookshot-deployment.yaml` : Deployment `matrix-hookshot` (`halfshot/matrix-hookshot:latest`) montant `config.yml`, `registration.yml` et `passkey.pem` dans `/data/`.
- `matrix-hookshot-httpproxy.yaml` : `HTTPProxy` Contour `hookshot-proxy` exposant `hookshot.etsmtl.club` vers `matrix-hookshot:9000`.
- `matrix-hookshot-service.yaml` : Service ClusterIP `matrix-hookshot` exposant les ports `9993` (appservice) et `9000` (webhooks).

## Dépendances

- Secret manuel `matrix-hookshot-secret` dans le namespace `matrix` contenant `registration.yaml` (également monté dans Synapse via `matrix-stack/values.yaml`) et la clé RSA `passkey.pem`.
