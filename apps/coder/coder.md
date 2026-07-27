# Coder

Environnements de dev distants, déployés dans le namespace `coder` (control
plane) + `coder-workspaces` (pods des workspaces).

- URL : https://coder.etsmtl.club
- Wildcard (apps/ports de workspace) : `*.coder.etsmtl.club`

## Auth

OIDC via Authentik, provider provisionné par
`terraform/coder/authentik-vault` (appliqué par `.github/workflows/apply-tf.yml`,
module `coder`). Le secret `coder-oidc-secret` (kv Vault
`kv/data/coder/default/coder-oidc-secret`) est synchronisé dans le namespace
`coder` par `apps/coder/resources/vault.yaml`.

**Group sync (OSS)** : le claim `groups` (scope mapping custom `coder-scope-groups`
dans le module terraform) réplique les groupes Authentik en groupes Coder
(`CODER_OIDC_GROUP_AUTO_CREATE=true`).

**Pas de role sync** : la promotion automatique groupe→rôle site (`Owner`,
`Auditor`, `Template Admin`) est une fonctionnalité Premium/Enterprise, absente
de Coder Community. Les rôles admin sont assignés **manuellement** après le
premier login OIDC de la personne :

```sh
coder users list
coder users edit-roles <username> --site-role owner
```

## Rotation du secret OIDC

Le client secret est généré par `random_password` dans
`terraform/coder/authentik-vault/main.tf`. Pour le faire tourner : `terraform
taint`/re-`apply` la ressource `random_password.coder_client_secret` (ou
relancer le workflow `apply-tf.yml` après un changement du module), ce qui
régénère le secret côté Authentik et le réécrit dans Vault. Le
`VaultStaticSecret` re-synchronise automatiquement le secret Kubernetes.

## Base de données

CNPG (`apps/coder/resources/postgres.yaml`), storageClass `ceph-rbd` (pas
`cephfs`), secret applicatif auto-généré `coder-pg-app` (clé `uri` utilisée
directement comme `CODER_PG_CONNECTION_URL`). Backup quotidien vers B2 via
barman-cloud.

## Workspaces

Provisionner via Kubernetes (pods dans `coder-workspaces`, isolé du control
plane par RBAC scopée + `ResourceQuota`/`LimitRange`, voir
`apps/coder/resources/workspaces-namespace.yaml`).

Template par défaut : `apps/coder/templates/kubernetes/main.tf`. Pas géré par
ArgoCD -- à pousser manuellement (ou via CI) :

```sh
coder templates push kubernetes -d apps/coder/templates/kubernetes
```

Home dir persistant par workspace sur `ceph-rbd` (taille configurable au
provisioning, paramètre `home_disk_size`).
