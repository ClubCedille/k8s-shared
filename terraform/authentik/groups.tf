# Groupes générés par clubs (voir locals.tf).
resource "authentik_group" "club" {
  for_each = toset(local.clubs)
  name     = "club-${each.key}"
  roles    = can(local.club_group_roles[each.key]) ? [local.club_group_roles[each.key]] : []
}

resource "authentik_group" "exec" {
  for_each = toset(local.clubs)
  name     = "exec-${each.key}"
  roles    = [authentik_rbac_role.exec[each.key].id]
}

# Groupes supplémentaires déclarés par club (voir data/authentik-extra-groups.yaml).
resource "authentik_group" "extra" {
  for_each = toset(local.authentik_extra_groups)
  name     = each.key
}

resource "authentik_group" "proxmox-user" {
  for_each = { for c in local.proxmox : c.name => c.group }
  name     = "${each.value}-user"
}

resource "authentik_group" "proxmox-exec" {
  for_each = { for c in local.proxmox : c.name => c.group }
  name     = "${each.value}-admin"
}

# Autres groupes
resource "authentik_group" "authentik_admins" {
  name         = "authentik Admins"
  is_superuser = true
}

resource "authentik_group" "admin" {
  name         = "admin"
  is_superuser = false
}

resource "authentik_group" "authentik_agent-users" {
  name  = "authentik Agent-Users"
  roles = [authentik_rbac_role.authentik_agent-users.id]
}

resource "authentik_group" "authentik_read-only" {
  name  = "authentik Read-only"
  roles = [authentik_rbac_role.authentik_read-only.id]
}

resource "authentik_group" "gcp-editors" {
  name = "gcp-editors"
}

resource "authentik_group" "gcp-viewers" {
  name = "gcp-viewers"
}

resource "authentik_group" "grafana-dashboard-creators" {
  name = "grafana-dashboard-creators"
}

resource "authentik_group" "grafana-metrics-explorers" {
  name = "grafana-metrics-explorers"
}

resource "authentik_group" "netbox-admin" {
  name = "netbox-Admin"
}

resource "authentik_group" "netbox-editor" {
  name = "netbox-Editor"
}

resource "authentik_group" "netbox-viewer" {
  name = "netbox-Viewer"
}

resource "authentik_group" "ocisadmin" {
  name = "ocisAdmin"
}

resource "authentik_group" "ocisuser" {
  name = "ocisUser"
}

resource "authentik_group" "omni-admin" {
  name = "omni-admin"
}

resource "authentik_group" "omni-user" {
  name = "omni-user"
}

resource "authentik_group" "omni-viewer" {
  name = "omni-viewer"
}

resource "authentik_group" "summercamp" {
  name = "summercamp"
}

resource "authentik_group" "formulemaster_capitaines" {
  name = "formulemaster-capitaines"
}

resource "authentik_group" "formulemaster_gestionnaires_beton" {
  name = "formulemaster-gestionnaires-beton"
}

resource "authentik_group" "formulemaster_users" {
  name = "formulemaster-users"
}
