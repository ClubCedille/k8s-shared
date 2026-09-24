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

# club-*/exec-* groups are generated from data/clubs.yaml (see locals.tf).
# Each exec group is bound to its exec-{club} role, which holds the object
# permissions (view/add/remove users) on the exec-{club} and club-{club} groups.
resource "authentik_group" "club" {
  for_each = toset(local.clubs)
  name     = "club-${each.key}"
}

resource "authentik_group" "exec" {
  for_each = toset(local.clubs)
  name     = "exec-${each.key}"
  roles    = [authentik_rbac_role.exec[each.key].id]
}

# "exec-test" is not a club: kept as a standalone group without exec-base.
resource "authentik_group" "exec-test" {
  name = "exec-test"
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

resource "authentik_group" "proxmox-cedille-apps-admin" {
  name = "proxmox-cedille-apps-admin"
}

resource "authentik_group" "proxmox-cedille-apps-user" {
  name = "proxmox-cedille-apps-user"
}

resource "authentik_group" "proxmox-dci-admin" {
  name = "proxmox-dci-admin"
}

resource "authentik_group" "proxmox-dci-user" {
  name = "proxmox-dci-user"
}

resource "authentik_group" "proxmox-eclipse-admin" {
  name = "proxmox-eclipse-admin"
}

resource "authentik_group" "proxmox-eclipse-user" {
  name = "proxmox-eclipse-user"
}

resource "authentik_group" "proxmox-gameservers-admin" {
  name = "proxmox-gameservers-admin"
}

resource "authentik_group" "proxmox-gameservers-user" {
  name = "proxmox-gameservers-user"
}

resource "authentik_group" "proxmox-k8s-cedille-prod-admin" {
  name = "proxmox-k8s-cedille-prod-admin"
}

resource "authentik_group" "proxmox-k8s-cedille-prod-user" {
  name = "proxmox-k8s-cedille-prod-user"
}

resource "authentik_group" "proxmox-k8s-cedille-sandbox-admin" {
  name = "proxmox-k8s-cedille-sandbox-admin"
}

resource "authentik_group" "proxmox-k8s-cedille-sandbox-user" {
  name = "proxmox-k8s-cedille-sandbox-user"
}

resource "authentik_group" "proxmox-k8s-poc-admin" {
  name = "proxmox-k8s-poc-admin"
}

resource "authentik_group" "proxmox-k8s-poc-user" {
  name = "proxmox-k8s-poc-user"
}

resource "authentik_group" "proxmox-k8s-shared-admin" {
  name = "proxmox-k8s-shared-admin"
}

resource "authentik_group" "proxmox-k8s-shared-user" {
  name = "proxmox-k8s-shared-user"
}

resource "authentik_group" "proxmox-lanets-admin" {
  name = "proxmox-lanets-admin"
}

resource "authentik_group" "proxmox-lanets-user" {
  name = "proxmox-lanets-user"
}

resource "authentik_group" "proxmox-management-infra-admin" {
  name = "proxmox-management-infra-admin"
}

resource "authentik_group" "proxmox-management-infra-user" {
  name = "proxmox-management-infra-user"
}

resource "authentik_group" "proxmox-networking-core-admin" {
  name = "proxmox-networking-core-admin"
}

resource "authentik_group" "proxmox-networking-core-user" {
  name = "proxmox-networking-core-user"
}

resource "authentik_group" "summercamp" {
  name = "summercamp"
}

resource "authentik_group" "test-terraform" {
  name = "test-terraform"
}