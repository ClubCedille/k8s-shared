# Automatisation Terraform

Chaque dossier sous `terraform/` est un **root Terraform indépendant**
(`tofu init`/`plan`/`apply` depuis son propre dossier), avec un backend
Kubernetes partagé via `~/.kube/config`:

- `authentik/` — groupes, rôles et config de marque Authentik (`state-authentik`);
- `outline/authentik-vault/`, `nodered/authentik-vault/`, `coder/authentik-vault/`,
  `matomo/authentik-vault/` — applications OIDC + secrets Vault.

Le workflow `.github/workflows/apply-tf.yml` détecte les changements et
applique les modules concernés lorsqu'un changement est intégré à `main`.
Sur `pull_request`, il ne fait que planifier.

## Authentification à Vault

Le workflow utilise GitHub Actions OIDC pour s'authentifier à
`https://vault.etsmtl.club`. Il n'utilise aucun `VAULT_TOKEN` stocké.

Le rôle JWT et la politique Vault sont gérés dans :

```text
ClubCedille/k8s-base/common/vault/overlays/k8s-shared/github-actions-oidc.yaml
```

Cette configuration doit être fusionnée et synchronisée par Argo CD avant le
changement du workflow. Le Token Vault créé :

- est valide pendant au plus 30 minutes;
- est limité à ce dépôt, à `main` et à ce workflow;
- ne peut gérer que les chemins Vault utilisés par les modules.

`workflow_dispatch` permet de choisir manuellement un ou tous les modules
(`auth-only` ne fait que vérifier l'authentification).