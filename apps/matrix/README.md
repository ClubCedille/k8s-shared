# Matrix / MatrixRTC

Synapse (chart `ananace/matrix-synapse`) + Cinny, avec backend MatrixRTC
hébergé : **LiveKit SFU + lk-jwt-service** en application service.

## Réseau : profiter de la DMZ

Les nodes portant `etsmtl.club/external-network: "true"` ont leur IP publique
directement en DMZ. Il n'y a donc **ni règle OPNsense, ni IP MetalLB
supplémentaire, ni NAT** à ajouter pour le média WebRTC :

- **Signalisation + JWT** : `matrix-rtc.etsmtl.club` passe par Contour
  (`HTTPProxy`) sur le VIP existant `.75`, avec un certificat cert-manager.
  - `/livekit/sfu` → LiveKit `:7880` (WebSocket, prefix stripping inclus)
  - `/livekit/jwt/` → lk-jwt-service `:8080` (prefix stripping inclus)
- **Média + TURN** : `livekit` tourne en `Deployment` (pas de `hostNetwork`, le
  namespace applique PSA `baseline`) derrière un `Service LoadBalancer` sur
  **`142.137.247.79`** (pool `matrix-rtc-ip` dans `system/metallb-extra`) :
  - TCP `7881` (ICE sur TCP)
  - TCP `443` (TURN/TLS, hostname `turn.etsmtl.club`, certificat `turn-rtc-tls`)
    — seul port TCP autorisé par le firewall Université sur `.79` (le `5349`
    sera réutilisé si les ITs l'ouvrent un jour)
  - UDP `50000` (média, via le **UDP mux** de LiveKit : `rtc.udp_port`, un seul
    port au lieu d'une plage), `50001` (TURN/UDP), `50002-50005` (relais TURN)

Kubernetes ne sait pas exposer une plage UDP dans un `Service` : il faut une
entrée par port. Le UDP mux permet de réduire le média à **un seul port** ; si
le débit devient insuffisant, passer `rtc.udp_port: 50000-50007` et ajouter les
ports correspondants dans le Service.

Les nodes ont des IP privées : les IP publiques sont des VIP MetalLB en DMZ.
On annonce donc explicitement `rtc.node_ip: 142.137.247.79` (avec
`use_external_ip: false`) comme candidate ICE. Le A record
`turn.etsmtl.club -> 142.137.247.79` est créé par external-dns via l'annotation
sur le Service.

## Secret à créer manuellement

Le secret `matrix-rtc-secrets` n'est pas versionné (il contient des tokens).
À créer dans le namespace `matrix` avant le premier sync ArgoCD :

```sh
AS_TOKEN=$(openssl rand -hex 32)
HS_TOKEN=$(openssl rand -hex 32)

cat > /tmp/opencode/registration.yaml <<EOF
id: "LiveKit JWT service"
as_token: "${AS_TOKEN}"
hs_token: "${HS_TOKEN}"
sender_localpart: "_lk_jwt_service"
namespaces:
  users:
    - exclusive: false
      regex: ".*"
url: null
io.element.msc4502.scopes:
  - "urn:matrix:client:io.element.msc4502:rooms:is_joined"
io.element.msc4512.proxy_prefix: "rtc/livekit"
io.element.msc4512.proxy_url: "http://lk-jwt-service.matrix.svc.cluster.local:8080"
EOF

kubectl -n matrix create secret generic matrix-rtc-secrets \
  --from-literal=livekit-key="$(openssl rand -hex 16)" \
  --from-literal=livekit-secret="$(openssl rand -hex 32)" \
  --from-file=registration.yaml=/tmp/opencode/registration.yaml
```

Les mêmes valeurs `as_token` / `hs_token` sont lues par Synapse (fichier
monté) et par lk-jwt-service (`LIVEKIT_AS_REGISTRATION_FILE`), donc elles ne
doivent apparaître que dans ce secret.

## Vérifications

```sh
kubectl -n matrix rollout status daemonset/livekit
kubectl -n matrix rollout status deployment/lk-jwt-service
kubectl -n matrix rollout status deployment/matrix-stack-matrix-synapse

curl https://matrix.etsmtl.club/.well-known/matrix/client | jq '.["org.matrix.msc4143.rtc_foci"]'
curl https://matrix-rtc.etsmtl.club/livekit/jwt/healthz
curl https://matrix.etsmtl.club/_matrix/client/v1/rtc/transports
```

Un appel Cinny doit ensuite afficher la liste des participants et se
connecter au SFU sans erreur « Your homeserver does not support calling ».

## Pourquoi pas coturn ?

`m.call` (1:1 legacy) utilise `turn_uris` + `turn_shared_secret` sur Synapse.
MatrixRTC utilise un SFU : LiveKit embarque son propre TURN avec une auth
dynamique, ce qui évite de gérer un secret partagé statique et un well-known
`m.turn` supplémentaire.
