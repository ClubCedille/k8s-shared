terraform {
  required_version = ">=1.14"

  backend "kubernetes" {
    secret_suffix = "state-penpot"
    namespace     = "terraform"
    config_path   = "~/.kube/config"
  }

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.8.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.9.0"
    }
  }
}

provider "authentik" {
  url   = "https://auth.etsmtl.club"
  token = var.AUTHENTIK_API_TOKEN
}

provider "vault" {
  address          = "https://vault.etsmtl.club"
  skip_child_token = true
}

locals {
  app_slug     = "penpot"
  app_name     = "Penpot"
  namespace    = "penpot"
  hostname     = "penpot.prodv2.cedille.club"
  vault_secret = "kv/data/${local.namespace}/default/penpot-oidc-secret"
}

module "oidc" {
  source = "../../modules/oidc-app"

  app_slug         = local.app_slug
  app_name         = local.app_name
  grant_types      = ["authorization_code", "refresh_token"]
  signing_key_name = "authentik Self-signed Certificate"

  redirect_uris = [
    {
      url = "https://${local.hostname}/api/auth/oidc/callback"
    },
  ]
}

resource "vault_kv_secret" "penpot_oidc_secret" {
  path = local.vault_secret

  data_json = jsonencode({
    OIDC_CLIENT_ID     = module.oidc.client_id
    OIDC_CLIENT_SECRET = module.oidc.client_secret
  })
}

moved {
  from = random_password.penpot_client_secret
  to   = module.oidc.random_password.client_secret[0]
}

moved {
  from = authentik_provider_oauth2.penpot
  to   = module.oidc.authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.penpot
  to   = module.oidc.authentik_application.application
}
