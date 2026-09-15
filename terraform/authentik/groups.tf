resource "authentik_group" "test-terraform" {
  name = "test-terraform"
}

resource "authentik_group" "admin" {
  name = "admin"
}