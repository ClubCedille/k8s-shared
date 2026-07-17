terraform {
  required_version = ">=1.14"
  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2025.10.1"
    }
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}
