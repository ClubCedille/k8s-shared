resource "authentik_group" "authentik_admins" {
  name = "authentik Admins"
}

resource "authentik_group" "admin" {
  name = "admin"
}

resource "authentik_group" "authentik_agent-users" {
  name = "authentik Agent-Users"

  roles = [
    authentik_rbac_role.authentik_agent-users.id,
  ]
}

resource "authentik_group" "authentik_read-only" {
  name = "authentik Read-only"

  roles = [
    authentik_rbac_role.authentik_read-only.id,
  ]
}

resource "authentik_group" "club-algoets" {
  name = "club-algoets"

  roles = [
    authentik_rbac_role.exec-algoets.id,
  ]
}

resource "authentik_group" "club-applets" {
  name = "club-applets"
}

resource "authentik_group" "club-baja" {
  name = "club-baja"
}

resource "authentik_group" "club-canoe" {
  name = "club-canoe"
}

resource "authentik_group" "club-capra" {
  name = "club-capra"
}

#resource "authentik_group" "admin" {
#  name = "admin"
#  is_superuser = false
#}

resource "authentik_group" "club-cedille" {
  name = "club-cedille"

  roles = [
    authentik_rbac_role.club-cedille.id,
  ]
}

resource "authentik_group" "club-chinook" {
  name = "club-chinook"
}

resource "authentik_group" "club-comets" {
  name = "club-comets"
}

resource "authentik_group" "club-conjure" {
  name = "club-conjure"
}

resource "authentik_group" "club-eclipse" {
  name = "club-eclipse"
}

resource "authentik_group" "club-jdgets" {
  name = "club-jdgets"
}

resource "authentik_group" "club-lanets" {
  name = "club-lanets"

  roles = [
    authentik_rbac_role.club-lanets.id,
  ]
}

resource "authentik_group" "club-musiquets" {
  name = "club-musiquets"
}

resource "authentik_group" "club-pontacier" {
  name = "club-pontacier"
}

resource "authentik_group" "club-raconteursdangle" {
  name = "club-raconteursdangle"
}

resource "authentik_group" "club-synapse" {
  name = "club-synapse"
}

resource "authentik_group" "club-veloom" {
  name = "club-veloom"
}

resource "authentik_group" "exec-algoets" {
  name = "exec-algoets"

  roles = [
    authentik_rbac_role.exec-algoets.id,
  ]
}

resource "authentik_group" "exec-applets" {
  name = "exec-applets"
}

resource "authentik_group" "exec-baja" {
  name = "exec-baja"

  roles = [
    authentik_rbac_role.exec-baja.id,
  ]
}

resource "authentik_group" "exec-canoe" {
  name = "exec-canoe"

  roles = [
    authentik_rbac_role.exec-canoe.id,
  ]
}

resource "authentik_group" "exec-capra" {
  name = "exec-capra"

  roles = [
    authentik_rbac_role.exec-capra.id,
  ]
}

resource "authentik_group" "exec-cedille" {
  name = "exec-cedille"

  roles = [
    authentik_rbac_role.exec-cedille.id,
  ]
}

resource "authentik_group" "exec-chinook" {
  name = "exec-chinook"

  roles = [
    authentik_rbac_role.exec-chinook.id,
  ]
}

resource "authentik_group" "exec-comets" {
  name = "exec-comets"

  roles = [
    authentik_rbac_role.exec-comets.id,
  ]
}

resource "authentik_group" "exec-conjure" {
  name = "exec-conjure"

  roles = [
    authentik_rbac_role.exec-conjure.id,
  ]
}

resource "authentik_group" "exec-eclipse" {
  name = "exec-eclipse"
}

resource "authentik_group" "exec-jdgets" {
  name = "exec-jdgets"
}

resource "authentik_group" "exec-lanets" {
  name = "exec-lanets"

  roles = [
    authentik_rbac_role.exec-lanets.id,
  ]
}

resource "authentik_group" "exec-musiquets" {
  name = "exec-musiquets"

  roles = [
    authentik_rbac_role.exec-musiquets.id,
  ]
}

resource "authentik_group" "exec-pontacier" {
  name = "exec-pontacier"

  roles = [
    authentik_rbac_role.exec-pontacier.id,
  ]
}

resource "authentik_group" "exec-raconteursdangle" {
  name = "exec-raconteursdangle"

  roles = [
    authentik_rbac_role.exec-raconteursdangle.id,
  ]
}

resource "authentik_group" "exec-synapse" {
  name = "exec-synapse"

  roles = [
    authentik_rbac_role.exec-synapse.id,
  ]
}

resource "authentik_group" "exec-test" {
  name = "exec-test"
}

resource "authentik_group" "exec-veloom" {
  name = "exec-veloom"

  roles = [
    authentik_rbac_role.exec-veloom.id,
  ]
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
