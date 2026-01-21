terraform {
  required_providers {
    authentik = {
      source = "goauthentik/authentik"
      version = "2025.10.1"
    }
  }
}

provider "authentik" {
  url = var.authentik_host
  token = var.authentik_token
}
