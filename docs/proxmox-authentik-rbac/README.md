# RBAC Proxmox via Authentik

## Contrat de nommage

Les cibles et le nom de base de leurs groupes Authentik sont déclarés ensemble
dans `data/proxmox.yaml` :

```yaml
- name: k8s-shared
  group: k8s-pmx-shared
```

Le root Terraform `terraform/authentik` crée deux groupes par cible :
`k8s-pmx-shared-user` (rôle Proxmox `PVEVMUser`) et
`k8s-pmx-shared-admin` (rôle Proxmox `PVEVMAdmin`) sur `/pool/Management`.

Les groupes sont synchronisés dans Proxmox via le realm **Authentik** de type
`openid`. Le rôle Ansible `cedille.proxmox.permissions` (dépôt `AnsibleRoles`)
ne gère ni utilisateurs ni groupes : il pilote uniquement les rôles/ACL
Proxmox. La correspondance `cible -> pool` vit dans
`AnsibleInfra/playbooks/proxmox/vars/permissions/`, source de vérité des droits.

## Renommage des anciens groupes `proxmox-*`

Les groupes historiques s'appelaient `proxmox-<cible>-{user,admin}`. Seuls les
attributs `name` changent ; les labels Terraform restent inchangés
(`proxmox-exec` conserve son label historique) pour éviter un destroy/recreate.

Ordre à respecter :

1. Appliquer ce root Terraform (CI `apply-tf.yml`) : les groupes Authentik
   portent désormais les noms déclarés dans `data/proxmox.yaml`.
2. Laisser les utilisateurs se reconnecter pour que la sync OIDC crée les
   nouveaux groupes côté Proxmox. Vérifier avec `pveum group list` sur `pve01`.
3. Dans `AnsibleInfra`, passer `permissions_revoke_legacy: true` puis lancer
   `make proxmox/permissions` pour révoquer les 22 ACL des anciens groupes.
4. Nettoyer manuellement les anciens groupes Proxmox s'ils subsistent.
