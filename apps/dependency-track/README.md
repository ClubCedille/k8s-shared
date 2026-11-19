# Dependency-Track (issue [#606](https://github.com/ClubCedille/k8s-shared/issues/606))

Inventaire central des composants (SBOM) et re-matching continu des CVE.
Premier lot : déploiement fondation. Le pont Trivy → Dependency-Track et les
notifications feront l'objet de MRs de suivi.

## Versions et provenance (vérifiées le 2026-11-19)

| Composant | Version | Référence |
|---|---|---|
| Chart Helm | `2.9.0` | `https://dependencytrack.github.io/helm-charts/` |
| Dependency-Track (appVersion du chart) | `5.2.1` | [release](https://github.com/DependencyTrack/dependency-track/releases/tag/5.2.1) |
| API server | `dependencytrack/apiserver@sha256:a7ce7a42928c6c03e94e8255e2ee871f5268f55b638a69729cae7afc47ef43b8` | tag `5.2.1` résolu via registry-1.docker.io |
| Frontend | `dependencytrack/frontend@sha256:1c0f63b083af8e89ff4ede5e7ed5cfc4e23ab871fa140ed101e8dc56f53eb51c` | tag `5.2.1` résolu via registry-1.docker.io |
| PostgreSQL | CloudNativePG `17.2` | même image que les autres apps du dépôt |

Le tarball du chart est signé. Vérification reproduite localement :

```sh
curl -fsSLO https://github.com/DependencyTrack/helm-charts/releases/download/dependency-track-2.9.0/dependency-track-2.9.0.tgz
curl -fsSLO https://github.com/DependencyTrack/helm-charts/releases/download/dependency-track-2.9.0/dependency-track-2.9.0.tgz.prov
curl -fsSL https://raw.githubusercontent.com/DependencyTrack/helm-charts/main/KEYS -o KEYS
gpg --dearmor < KEYS > keys.gpg
helm verify dependency-track-2.9.0.tgz --keyring keys.gpg
# Signed by: OWASP Dependency-Track Helm Charts <dependencytrack+helm@owasp.org>
# Fingerprint: 9E84D97EE40FC91081E0AB5CDA73BC27D109A385
```

Aucun tag flottant : la version du chart est épinglée dans `kustomization.yaml`
et les deux images par digest dans `helm/values.yaml`. Renovate gardera ces
références à jour.

## Architecture

- **Namespace** `dependency-track` sur `k8s-shared` (`destination.server:
  https://kubernetes.default.svc`, projet ArgoCD `k8s-shared`).
- **API server** en monolithe (`api-server:8080`), health/metrics sur le port
  management `9000`, `ServiceMonitor` scrapé par le Prometheus in-cluster
  (`monitoring`) et remote-write vers Mimir.
- **Frontend** (`frontend:8080`), exposé via `dependency-track.etsmtl.club`
  (HTTPProxy Contour + certificat `letsencrypt-etsmtl`). `/api` est routé vers
  l'API server.
- **PostgreSQL externe** : cluster CNPG `postgresql-dependency-track` (3
  instances, `ceph-rbd` 20 Gi), base `dtrack`, owner `dtrack` (l'API exécute
  des DDL au démarrage et pour les partitions). Sauvegardes quotidiennes
  via barman-cloud vers B2, rétention 30 jours.
- **Stockage fichiers** : PVC `ceph-rbd` 20 Gi monté sur `/data` (SBOM).
- **Secrets** : tous viennent de Vault via `VaultStaticSecret` — credentials
  DB (`kubernetes.io/basic-auth`), KEK de chiffrement des secrets applicatifs,
  client OIDC et credentials B2. Terraform les écrit dans
  `kv/data/dependency-track/default/*` et `kv-system/default_passwords/b2-creds`.
- **Auth** : SSO Authentik (client public PKCE, provisioning auto, team sync
  depuis le claim `groups`). Seuls les membres du groupe Authentik
  `dependency-track-users` peuvent se connecter.

## Ordre de déploiement

1. `terraform apply` dans `terraform/dependency-track/authentik-vault/` (avec
   `AUTHENTIK_API_TOKEN`) : crée l'app OIDC et écrit les 3 secrets Vault.
   Le CI `.github/workflows/apply-tf.yml` applique ce module après merge sur `main`.
2. L'app ArgoCD `dependency-track` se synchronise ensuite (les
   `VaultStaticSecret` créent les Secrets Kubernetes, puis CNPG démarre).
3. Vérifier :

```sh
kubectl -n dependency-track get pods -w
kubectl -n dependency-track get vaultstaticsecret
kubectl -n dependency-track get cluster.postgresql.cnpg.io postgresql-dependency-track
kubectl -n monitoring get servicemonitor dependency-track-api-server-metrics
curl -fsS https://dependency-track.etsmtl.club/health/ready
```

## Après le premier déploiement (à faire manuellement)

1. **Compte admin par défaut** : le premier boot crée `admin`/`admin`. Comme
   l'OIDC est activé, se connecter une fois avec Authentik, puis désactiver
   (ou supprimer) le compte local `admin` dans *Administration → Access
   Management → Users*.
2. **Sources de vulnérabilités** (*Administration → Vulnerability Sources*) :
   activer **NVD** (pas de clé requise), **GitHub Advisories** (PAT ou GitHub
   App ; le PAT partagé `ghcr` peut être réutilisé en lecture seule) et **OSV**
   (sélectionner au minimum l'écosystème Debian). Lancer « Mirror now » pour
   chacune — le premier mirroring NVD est long.
3. **Équipe et clé API pour le pont SBOM** (obligatoire, voir section ci-dessous).
4. **Notifications** : dans *Administration → Notifications → Publishers*, créer
   un publisher **Webhook** pointant vers notre canal habituel (Discord/Matrix),
   puis une politique *Notification Rule* sur sévérité **critique/haute** avec
   `New vulnerability` et `BOM processed` comme événements. Tester avec une
   notification de test. Ces objets sont configurés via l'UI/API de DT (aucune
   variable d'environnement ne les supporte) : ils sont sauvegardés dans la base
   PostgreSQL, donc couverts par les sauvegardes B2.
5. **Restauration** : tester une fois la restauration d'une sauvegarde B2 sur
   un cluster de test, puis documenter la procédure dans le wiki (issue #606).

## Pont SBOM (`bridge/`)

CronJob quotidien `dependency-track-sbom-bridge` (04h15, `concurrencyPolicy:
Forbid`) qui exporte les `SbomReport` de Trivy Operator vers Dependency-Track.

- Le champ `.report.components` de chaque CR est un document **CycloneDX**
  complet : il est envoyé tel quel à `PUT /api/v1/bom` avec `autoCreate: true`.
- Nommage des projets : `<cluster>/<namespace>/<workload>/<conteneur>` (ex.
  `k8s-shared/algoets-website/algoets-website-57988b5c76/nginx`) ; la version
  est le digest court de l'image.
- Un ConfigMap `sbom-bridge-state` mémorise la `resourceVersion` du dernier
  rapport uploadé par UID : seuls les BOM modifiés sont renvoyés. Supprimer ce
  ConfigMap force une resynchronisation complète.
- L'image Python est épinglée par digest ; le script n'utilise que la stdlib.
- RBAC minimal : `get/list` sur `sbomreports` (cluster-wide) et
  `get/create/update` sur le seul ConfigMap d'état.

### Créer la clé API (prérequis)

1. Dans DT : *Administration → Access Management → Teams* → créer une équipe
   `sbom-bridge`, lui donner les permissions `BOM_UPLOAD`, `PROJECT_CREATION_UPLOAD` (auto-create des projets
   lors de l'upload) et `VIEW_PORTFOLIO` — rien de plus.
2. *Administration → Access Management → API Keys* → créer une clé pour cette
   équipe et copier le token.
3. Écrire le token dans Vault (le `secret-reader` de Kubernetes peut lire ce
   chemin, mais pas l'écrire) :

   ```sh
   vault kv put kv/dependency-track/default/sbom-upload-token token="<token>"
   ```

4. Le `VaultStaticSecret` `dependency-track-sbom-token` crée alors le Secret
   Kubernetes ; le CronJob peut démarrer. Sans token, le job s'arrête avec un
   message explicite (le volume est `optional: true` pour ne pas bloquer le pod).

Vérification :

```sh
kubectl -n dependency-track create job --from=cronjob/dependency-track-sbom-bridge sbom-bridge-manual
kubectl -n dependency-track logs job/sbom-bridge-manual -f
```

## Dépannage : `password authentication failed for user "dtrack"`

Si CNPG a démarré **avant** que le `VaultStaticSecret` ne crée
`dependency-track-db-secret`, l'initdb génère un mot de passe aléatoire et le
secret Vault écrase ensuite la valeur. Les `VaultStaticSecret` portent désormais
un sync-wave `-1` pour éviter ce cas. Sur un déploiement déjà installé,
réaligner le rôle PostgreSQL sur le secret courant :

```sh
pod=$(kubectl -n dependency-track get pods -o name | grep postgresql-dependency-track-1 | head -1 | cut -d/ -f2)
pass=$(kubectl -n dependency-track get secret dependency-track-db-secret -o jsonpath='{.data.password}' | base64 -d)
kubectl -n dependency-track exec "$pod" -- psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -c "ALTER ROLE dtrack WITH PASSWORD '$pass';"
```

## Reste à faire pour clore #606

- [ ] Politiques et notifications vers le canal habituel.
- [ ] Validation de l'exercice « trouver les projets affectés par une CVE en < 5 min ».
- [ ] Documentation wiki (recherche d'un composant, lecture d'un projet, faux positifs).
- [ ] (Optionnel) SBOM des hôtes via Syft/Ansible et des pipelines CI.
