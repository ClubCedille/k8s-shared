resource "authentik_rbac_role" "outline_sync_service" {
  name = "Outline Sync Service"
}

resource "authentik_rbac_role" "ak-managed-role--user-2" {
  name = "ak-managed-role--user-2"
}

resource "authentik_rbac_role" "ak-managed-role--user-256" {
  name = "ak-managed-role--user-256"
}

resource "authentik_rbac_role" "ak-migrated-role--user-12" {
  name = "ak-migrated-role--user-12"
}

resource "authentik_rbac_role" "ak-migrated-role--user-2" {
  name = "ak-migrated-role--user-2"
}

resource "authentik_rbac_role" "ak-migrated-role--user-77" {
  name = "ak-migrated-role--user-77"
}

resource "authentik_rbac_role" "authentik_agent-users" {
  name = "authentik Agent-Users"
}

resource "authentik_rbac_role" "authentik_read-only" {
  name = "authentik Read-only"
}

# club-{club} roles hold the club-scoped object permissions
# (change/view on the club-{club} group object). They are pre-existing and kept
# as individual resources because their permissions only exist in the
# Authentik UI/API (not expressible in this provider).
resource "authentik_rbac_role" "club-cedille" {
  name = "club-cedille"
}

resource "authentik_rbac_role" "club-eclipse" {
  name = "club-eclipse"
}

resource "authentik_rbac_role" "club-jdgets" {
  name = "club-jdgets"
}

resource "authentik_rbac_role" "club-lanets" {
  name = "club-lanets"
}

# Per-club exec roles hold the object permissions for their club:
# view/add_user/remove_user on the exec-{club} and club-{club} group objects.
# Those grants only exist in the Authentik UI/API (not expressible in this
# provider); scripts/reconcile-exec-perms.sh keeps them in sync. exec-applets
# is materialized here because it has no upstream role yet.
resource "authentik_rbac_role" "exec" {
  for_each = toset(local.clubs)
  name     = "exec-${each.key}"
}

resource "authentik_rbac_role" "exec-test" {
  name = "exec-test"
}

resource "authentik_rbac_role" "mcp" {
  name = "mcp"
}