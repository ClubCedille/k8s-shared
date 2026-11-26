# LiveKit / MatrixRTC

Backend **MatrixRTC** (appels audio/vidéo) composé du SFU **LiveKit** (avec TURN intégré) et du service d'autorisation **lk-jwt-service**.

## Ressources

- `livekit-configmap.yaml` : ConfigMap `livekit-config` (modèle `livekit.yaml` : signalisation `:7880`, ICE/TCP `:7881`, UDP mux `:50000`, TURN `turn.etsmtl.club`, Redis `matrix-stack-redis-master:6379` db `3`).
- `livekit-deployment.yaml` : Deployment `livekit` (`livekit/livekit-server:v1.13.11`) avec initContainer `render-config` injectant les clés/mots de passe depuis `matrix-rtc-secrets` et `matrix-stack-redis`.
- `livekit-service.yaml` : Service ClusterIP `livekit` pour la signalisation (`7880`) et les métriques Prometheus (`6789`).
- `livekit-media-service.yaml` : Service LoadBalancer `livekit-media` (`142.137.247.77`) exposant ICE/TCP, TURN/TLS (`5349`), le média UDP (`50000`) et les relais TURN (`50001-50005`), avec annotation `external-dns` pour `turn.etsmtl.club`.
- `lk-jwt-deployment.yaml` : Deployment `lk-jwt-service` (`ghcr.io/element-hq/lk-jwt-service:0.10.0`).
- `lk-jwt-service.yaml` : Service ClusterIP `lk-jwt-service` sur le port `8080`.
- `matrix-rtc-certificate.yaml` : Certificat cert-manager `matrix-rtc-cert` (secret `matrix-rtc-tls`) pour `matrix-rtc.etsmtl.club`.
- `matrix-rtc-httpproxy.yaml` : `HTTPProxy` Contour `matrix-rtc-proxy` routant `/livekit/jwt/` vers `lk-jwt-service` et `/livekit/sfu` vers `livekit`.
- `matrix-rtc-networkpolicy.yaml` : `NetworkPolicy` pour `livekit` et `lk-jwt-service`.

## Dépendances

- Secret manuel `matrix-rtc-secrets` (voir le [README principal](../../README.md)).
- Certificat TURN `turn-rtc-tls` géré par [`../turn-certificate.yaml`](../turn-certificate.yaml).
- Redis déployé par le chart `matrix-synapse` (`matrix-stack-redis`).
