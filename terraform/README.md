# Automatisation Terraform

Le workflow `.github/workflows/apply-tf.yml` applique les modules
Authentik/Vault d'Outline et de Node-RED lorsque des changements sont intégrés
à `main`.

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
- peut uniquement gérer les chemins Vault utilisés par les modules Node-RED et
  Outline.

L'intégration d'un changement au workflow déclenche une exécution qui vérifie
uniquement l'authentification. Après sa réussite, lancer manuellement le
workflow avec `nodered`, `outline` ou `all` pour valider une véritable
application Terraform. L'option par défaut `auth-only` vérifie uniquement
l'échange OIDC.

Après la réussite d'une application Terraform, supprimer l'ancien secret
`VAULT_TOKEN` dans les paramètres du dépôt `ClubCedille/k8s-shared`.
