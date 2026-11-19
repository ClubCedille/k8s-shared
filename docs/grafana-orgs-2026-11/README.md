# Séparation Grafana en deux organisations (novembre 2026)

## Objectif

Avant : un seul org Grafana (l'org par défaut, id `1`, « Main Org. ») contenant
tous les dashboards et datasources, accessible en lecture à tout compte
Authentik qui se connecte (`allow_sign_up: true`).

Après :

| Org | Rôle des comptes | Contenu |
| --- | --- | --- |
| `Cedille` (id 1, **renommée**) | Viewer pour tous ; Editor pour `grafana-dashboard-creators` / `grafana-metrics-explorers` | Tous les dashboards et datasources existants, inchangés |
| `Lan_ETS` (nouvelle) | Admin / Editor / Viewer selon le groupe Authentik | Vide pour l'instant (à provisionner séparément) |

`Lan_ETS` n'est **pas** assignée automatiquement : seuls les membres des
groupes `grafana-lanets-*` y sont ajoutés, au prochain login OIDC.

## Fichiers modifiés

- `apps/grafana/helm/values.yaml` : `org_attribute_path` + `org_mapping` dans
  `[auth.generic_oauth]` ; `role_attribute_path` inchangé (rôles dans Cedille).
  L'entrée `*:Cedille:Viewer` est essentielle : avec `org_mapping`, Grafana
  remplace l'ensemble des rôles d'org de l'utilisateur par ceux du mapping
  et retire l'appartenance aux orgs non listées. Sans elle, les membres
  `grafana-lanets-*` perdraient Cedille.
- `terraform/grafana/authentik-vault/main.tf` : trois nouveaux groupes
  Authentik `grafana-lanets-admin`, `grafana-lanets-editor`,
  `grafana-lanets-viewer`.
- `terraform/grafana/access/main.tf` : provider `grafana.admin` (basic auth),
  ressources `grafana_organization.cedille` et `.lan_ets`.
- `terraform/grafana/access/variables.tf` : variable `GRAFANA_ADMIN_AUTH`.

## Procédure d'application

Les modules `terraform/grafana/*` ne font **pas** partie de la matrice
`.github/workflows/apply-tf.yml` : ils s'appliquent manuellement.

### 1. Organisations (avant la synchro Helm)

Le compte local `admin` du chart Grafana est Server Admin. Son mot de passe
est fourni sous forme `admin:<password>` via la variable d'environnement
`TF_VAR_GRAFANA_ADMIN_AUTH` (aucun secret de ce type n'est encore stocké dans
Vault dans ce dépôt — à ajouter si tu veux le centraliser).

```bash
cd terraform/grafana/access
export TF_VAR_GRAFANA_SERVICE_ACCOUNT_TOKEN='<token du service account Admin>'
export TF_VAR_GRAFANA_ADMIN_AUTH='admin:<mot de passe admin local>'
tofu init

# Import unique de l'org existante : sans ça Terraform voudrait créer
# une seconde org "Cedille" et laisserait "Main Org." orpheline.
tofu import grafana_organization.cedille 1

tofu plan   # doit montrer : rename Main Org. -> Cedille, create Lan_ETS, rien d'autre
tofu apply
```

`ignore_changes` sur les listes de membres est volontaire : les utilisateurs
sont ajoutés aux orgs par OIDC, Terraform ne doit pas les retirer à chaque
apply.

### 2. Groupes Authentik

```bash
cd terraform/grafana/authentik-vault
export TF_VAR_AUTHENTIK_API_TOKEN='<token API Authentik>'
tofu init && tofu apply
```

### 3. Configuration Grafana

La PR fusionnée, laisser ArgoCD synchroniser l'app `grafana` (ou
`argocd app sync grafana`) pour charger le nouveau `org_mapping`.

### 4. Vérifications

- `GET /api/orgs` (admin) → `Cedille` (id 1) et `Lan_ETS`.
- Comptes test dans chaque groupe `grafana-lanets-*` : après **re-login**,
  le sélecteur d'org affiche `Lan_ETS` avec le bon rôle, et `Cedille` reste
  accessible en Viewer (vérifier explicitement ce second point : c'est le
  piège principal de `org_mapping`).
- Un compte sans groupe `grafana-lanets-*` ne voit pas `Lan_ETS`, mais garde
  `Cedille` (Viewer, ou Editor pour les deux groupes staff).
- Si la configuration semble ignorée, vérifier qu'aucun paramètre SSO n'a
  été enregistré en base via l'UI/API (les réglages stockés en base
  overrident `grafana.ini`).
- Les dashboards existants sont toujours présents dans `Cedille`.
- `tofu plan` est propre dans les deux modules après application.

## Limites connues / non traité

- `Lan_ETS` n'a ni datasource ni dashboard : Mimir/Loki y seront à créer
  (par exemple avec `grafana_data_source` + `org_id`) quand le besoin se
  précisera.
- Les Viewers de `Cedille` peuvent toujours interroger Loki via Explore :
  restreindre un datasource par rôle est une fonctionnalité Enterprise
  (cf. commentaire dans `terraform/grafana/access/main.tf`).
- Les groupes `grafana-dashboard-creators` et `grafana-metrics-explorers`
  sont définis dans **deux** roots Terraform indépendants
  (`terraform/authentik` et `terraform/grafana/authentik-vault`) : situation
  préexistante, non modifiée ici.
- Les rôles OIDC ne sont recalculés qu'au login : prévoir une déconnexion /
  reconnexion pour les utilisateurs déjà connectés.
