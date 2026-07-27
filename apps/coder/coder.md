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
`cephfs`). Backup quotidien vers B2 via barman-cloud.

**Le secret `coder-pg-app` doit être créé manuellement avant le premier
bootstrap du Cluster** -- vérifié empiriquement : `bootstrap.initdb.secret.name`
ne génère *pas* automatiquement le secret s'il n'existe pas déjà (le rôle
`coder` reste alors sans mot de passe, `rolpassword` null). Volontairement
**pas** commité dans git (contrairement à `postgresql-forgejo-app`/
`nextcloud-postgresql` ailleurs dans ce repo) :

```sh
kubectl create secret generic coder-pg-app \
  --type=kubernetes.io/basic-auth \
  --from-literal=username=coder \
  --from-literal=password="$(openssl rand -base64 32)" \
  -n coder
```

`CODER_PG_CONNECTION_URL` est composé dans `apps/coder/helm/values.yaml` via
l'expansion `$(VAR)` de Kubernetes à partir de `username`/`password` (ce
secret ne contient jamais de clé `uri`).

Si le Cluster doit être recréé (perte du mot de passe, migration...), ce
secret doit exister *avant* de réappliquer `postgres.yaml`, sinon répéter
l'étape ci-dessus avec un nouveau mot de passe.

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
