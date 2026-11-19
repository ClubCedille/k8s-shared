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
3. **Équipe et clé API pour le pont SBOM** : créer une équipe (ex. `sre`) et
   une clé API avec les seules permissions `BOM_UPLOAD` / `VIEW_PORTFOLIO`,
   puis stocker la clé dans Vault sous
   `kv/data/dependency-track/default/sbom-upload-token` pour le CronJob de la
   MR suivante.
4. **Notifications** : configurer un publisher webhook vers notre canal
   habituel, avec une politique « critique/haute » (MR de suivi).
5. **Restauration** : tester une fois la restauration d'une sauvegarde B2 sur
   un cluster de test, puis documenter la procédure dans le wiki (issue #606).

## Reste à faire pour clore #606

- [ ] Pont Trivy `SbomReport` → Dependency-Track (CronJob d'export + upload API).
- [ ] Politiques et notifications vers le canal habituel.
- [ ] Validation de l'exercice « trouver les projets affectés par une CVE en < 5 min ».
- [ ] Documentation wiki (recherche d'un composant, lecture d'un projet, faux positifs).
- [ ] (Optionnel) SBOM des hôtes via Syft/Ansible et des pipelines CI.
