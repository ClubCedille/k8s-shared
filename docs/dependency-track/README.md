# Dependency-Track — guide d'utilisation (contenu wiki)

Ce document est le contenu à copier dans le wiki Outline (issue #606). Les
commandes utilisent une clé API Dependency-Track lue depuis l'environnement :

```sh
export DT_URL=https://dependency-track.etsmtl.club
export DT_API_KEY='<clé API avec VIEW_PORTFOLIO>'
dtapi() { curl -fsS -H "X-Api-Key: $DT_API_KEY" -H 'Content-Type: application/json' "$@"; }
```

La clé `sbom-bridge` n'a que `BOM_UPLOAD`, `PROJECT_CREATION_UPLOAD` et
`VIEW_PORTFOLIO` : elle suffit pour la lecture décrite ici et l'upload, mais pas
pour marquer un faux positif (voir §4).

## 1. Chercher un composant dans tout le portefeuille

Dans l'UI : barre de recherche globale (en haut) → saisir le nom ou le PURL du
composant (`pkg:deb/debian/openssl`, `pkg:npm/lodash`, …). Les résultats
montrent les projets qui l'utilisent et les versions.

Via l'API, lister les composants d'un projet puis filtrer :

```sh
# UUID du projet (nommé <cluster>/<namespace>/<workload>/<conteneur> par le pont SBOM)
PROJECT_UUID=$(dtapi "$DT_URL/api/v1/project/lookup?name=k8s-shared%2Falgoets-website%2Falgoets-website-57988b5c76%2Fnginx" | jq -r '.[0].uuid')

# Tous les composants du projet, avec leur version et PURL
dtapi "$DT_URL/api/v1/component/project/$PROJECT_UUID" \
  | jq -r '.[] | [.name, .version, .purl] | @tsv' | sort -u
```

Pour un inventaire agrégé (toutes versions confondues) :

```sh
dtapi "$DT_URL/api/v1/project" \
  | jq -r '.[].uuid' \
  | while read -r u; do dtapi "$DT_URL/api/v1/component/project/$u"; done \
  | jq -r '[.name, .version, .purl] | @tsv' | sort -u
```

## 2. Exercice — « sommes-nous touchés par la CVE X ? » (< 5 min)

Dependency-Track rematche en continu les composants avec NVD, GitHub
Advisories et OSV. Endpoint dédié :

```sh
dtapi "$DT_URL/api/v1/vulnerability/source/NVD/vuln/CVE-2026-XXXX/projects" \
  | jq -r '.[] | [.name, .version] | @tsv'
```

Si la source est GitHub Advisories, remplacer `NVD` par `GITHUB` (et `OSV`
pour OSV). Le même endpoint sans `/projects` retourne le détail de la CVE.

Procédure :

1. Récupérer l'identifiant de la CVE (ex. `CVE-2026-114938`).
2. Appeler l'endpoint ci-dessus pour chaque source configurée.
3. Croiser avec la vue « Vulnerabilities » de l'UI pour la sévérité et la
   version correctrice.
4. Consigner le résultat (projets touchés + versions) dans l'incident.

## 3. Lire un projet / un SBOM

```sh
# Metadonnees du projet
dtapi "$DT_URL/api/v1/project/lookup?name=<name>" | jq '.[0]'

# Findings (vulnerabilites) du projet
dtapi "$DT_URL/api/v1/finding/project/$PROJECT_UUID" \
  | jq -r '.[] | [.component.name, .component.version, .vulnerability.vulnId, .vulnerability.severity] | @tsv'

# SBOM CycloneDX original tel qu'uploade par le pont
dtapi "$DT_URL/api/v1/bom/cyclonedx/project/$PROJECT_UUID" > bom.json
```

Un projet créé par le pont SBOM porte le nom
`<cluster>/<namespace>/<workload>/<conteneur>` et pour version le digest court
de l'image. Plusieurs versions d'un même projet correspondent à plusieurs
images déployées successivement.

## 4. Marquer un faux positif

Nécessite une clé avec `VULNERABILITY_ANALYSIS` (la clé `sbom-bridge` ne l'a
pas — utiliser un compte nominatif via l'UI ou une clé dédiée).

Dans l'UI : ouvrir le projet → onglet *Vulnerabilities* → sélectionner le
finding → *Analyze* → état `False Positive`, commentaire obligatoire.

Via l'API :

```sh
curl -fsS -X PUT -H "X-Api-Key: $DT_API_KEY" -H 'Content-Type: application/json' \
  "$DT_URL/api/v1/analysis" \
  -d '{"project":"'"$PROJECT_UUID"'","component":"'"$COMPONENT_UUID"'","vulnerability":"'"$VULN_UUID"'","analysisState":"FALSE_POSITIVE","comment":"Faux positif justifie - voir ticket XXX"}'
```

Toujours documenter la raison : un faux positif masque la CVE pour tout le
portefeuille.

## 5. Notifications

Les publishers et règles de notification se configurent dans
*Administration → Notifications* (aucune variable d'environnement ne les
supporte). Ils sont stockés dans PostgreSQL et donc couverts par les
sauvegardes barman-cloud quotidiennes vers B2.

- Publisher **Webhook** vers le canal habituel (Discord/Matrix), avec un
  template lisible (nom du projet, CVE, sévérité, version correctrice).
- Règle sur sévérité **critique** et **haute**, événements `NEW_VULNERABILITY`
  et `BOM_PROCESSED`.
- Tester avec « Send test notification », puis vérifier la réception dans le
  canal.

## 6. Sauvegarde et restauration

Voir `apps/dependency-track/README.md` : cluster CNPG `postgresql-dependency-track`,
sauvegardes quotidiennes 06h20 vers `s3://k8s-shared-bucket/postgresql-dependency-track`
(rétention 30 j). La restauration doit être testée au moins une fois sur un
cluster de test avant de considérer l'issue #606 close.
