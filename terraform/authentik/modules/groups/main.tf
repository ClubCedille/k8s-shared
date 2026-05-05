data "authentik_rbac_permission" "can_view_group" {
  codename = "Can view Group"
}

data "authentik_rbac_permission" "can_view_user" {
  codename = "Can view User"
}

data "authentik_rbac_permission" "can_access_admin_interface" {
  codename = "Can access admin interface"
}

resource "authentik_group" "exec" {
  name = "exec-${var.name}"
}

resource "authentik_group" "club" {
  name = "club-${var.name}"
}

# ---- GLOBAL ROLE PERMISSIONS ----

resource "authentik_rbac_initial_permissions" "exec_permissions" {
  name = "exec-${var.name}-role"
  role = authentik_group.exec.name
  mode = "role"

  permissions = [
    data.authentik_rbac_permission.can_view_user.id,
    data.authentik_rbac_permission.can_view_group.id,
    data.authentik_rbac_permission.can_access_admin_interface.id,
  ]
}

resource "authentik_rbac_initial_permissions" "club_permissions" {
  name = "club-${var.name}-role"
  role = authentik_group.club.name
  mode = "role"

  permissions = [
    data.authentik_rbac_permission.can_view_user.id,
    data.authentik_rbac_permission.can_view_group.id,
  ]
}

# ---- OBJECT PERMISSIONS FOR EXEC ----

locals {
  group_permissions = [
    "view_group",
    "change_group",
  ]
}

# exec can manage club group
resource "authentik_rbac_object_permission" "exec_manage_club" {
  for_each = toset(local.group_permissions)

  object_pk    = authentik_group.club.id
  content_type = "authentik_core.group"
  permission   = each.value
  role         = authentik_group.exec.name
}

# exec can manage exec group
resource "authentik_rbac_object_permission" "exec_manage_exec" {
  for_each = toset(local.group_permissions)

  object_pk    = authentik_group.exec.id
  content_type = "authentik_core.group"
  permission   = each.value
  role         = authentik_group.exec.name
}
