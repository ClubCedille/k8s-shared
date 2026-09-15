resource "authentik_group" "test-terraform" {
  name = "test-terraform"
}

#resource "authentik_group" "admin" {
#  name = "admin"
#  is_superuser = false
#}

resource "authentik_group" "club-cedille" {
  name = "club-cedille"
  is_superuser = false
  roles = [
    authentik_rbac_role.club-cedille.id
  ]
}

resource "authentik_rbac_role" "club-cedille" {
  name = "club-cedille"
}
#resource "authentik_group" "exec-cedille" {
#  name = "exec-cedille"
#  is_superuser = false
#}
