# Cinny

Client web Matrix léger ([Cinny](https://cinny.in/)), servi derrière Contour via [`../httpproxy.yaml`](../httpproxy.yaml).

## Ressources

- `cinny-configmap.yaml` : ConfigMap `cinny-config` définissant `config.json` avec le homeserver par défaut `matrix.etsmtl.club`.
- `cinny-deployment.yaml` : Deployment `cinny-deployment` (`ghcr.io/cinnyapp/cinny:v4.12.8`, port `80`) montant `config.json` dans `/app/config.json` et `/usr/share/nginx/html/config.json`.
- `cinny-service.yaml` : Service ClusterIP `cinny-deployment` exposant le port HTTP `80`.
