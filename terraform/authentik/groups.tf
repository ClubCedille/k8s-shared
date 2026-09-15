import {
    to = authentik_group.club-cedille
    id = 6071e045-b7f0-428c-aed9-ea23ebd53d5d
}

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
}

#resource "authentik_group" "exec-cedille" {
#  name = "exec-cedille"
#  is_superuser = false
#}

