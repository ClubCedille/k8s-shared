locals {
  # Les clubs sont tirés du fichier data/clubs.yaml
  clubs = sort(distinct(concat(
    [for c in yamldecode(file("${path.module}/../../data/clubs.yaml")) : c.name],
  )))

  # Rôles additionnels pour certains clubs qui nécessitent des rôles spécifiques
  club_group_roles = {
    "cedille" = authentik_rbac_role.club-cedille.id
    "lanets"  = authentik_rbac_role.club-lanets.id
  }
}
