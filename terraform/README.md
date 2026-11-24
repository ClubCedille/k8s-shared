# Automatisation Terraform

Chaque dossier sous `terraform/` est un **root Terraform indépendant**
(`tofu init`/`plan`/`apply` depuis son propre dossier), avec un backend
Kubernetes partagé via `~/.kube/config`:

- `authentik/` — groupes, rôles et config de marque Authentik (`state-authentik`);
- `*/authentik-vault/` — applications OIDC + secrets Vault (`outline`,
  `nodered`, `coder`, `dependency-track`, `grafana`, `hi-events`, `inventree`,
  `matomo`, `penpot`, `policy-reporter`).

## Module partagé `modules/oidc-app`

Les roots `*/authentik-vault` ne déclarent plus chacun leur provider OAuth2,

leur application Authentik et leurs data sources : le squelette commun vit
dans `terraform/modules/oidc-app` (client secret, provider, application,
policy binding optionnel, scope `groups` optionnel). Un root ne garde que ses
spécificités (URI de redirection, validité des tokens, secrets Vault, groupes
et ressources propres à l'application).

Les roots restent des states séparés. Lorsqu'un root est migré vers le
module, ses anciennes adresses de ressources sont redirigées avec des blocs
`moved` (et `removed` pour les objets désormais gérés par `terraform/authentik`),
afin de ne rien détruire ni régénérer de client secret.

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