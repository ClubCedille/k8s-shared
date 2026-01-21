module "authentik" {
  source = "./authentik"

  authentik_url = var.authentik_url
  authentik_token = var.authentik_token
}
