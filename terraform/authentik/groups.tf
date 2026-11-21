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

resource "authentik_group" "proxmox-user" {
  for_each = toset(local.proxmox)
  name     = "proxmox-${each.key}-user"
}

resource "authentik_group" "proxmox-exec" {
  for_each = toset(local.proxmox)
  name     = "proxmox-${each.key}-admin"
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
