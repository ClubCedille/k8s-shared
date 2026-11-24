terraform {
  required_version = ">=1.14"

  backend "kubernetes" {
    secret_suffix = "state-hi-events"
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
  app_slug     = "hi-events"
  app_name     = "Hi.Events"
  namespace    = "hi-events"
  hostname     = "events.etsmtl.club"
  vault_secret = "kv/data/${local.namespace}/default/hi-events-oidc-secret"
}

module "oidc" {
  source = "../../modules/oidc-app"

  app_slug         = local.app_slug
  app_name         = local.app_name
  grant_types      = ["authorization_code", "refresh_token"]
  signing_key_name = "authentik Self-signed Certificate"

  redirect_uris = [
    {
      url = "https://${local.hostname}/sso/callback"
    },
  ]
}

resource "vault_kv_secret" "hi_events_oidc_secret" {
  path = local.vault_secret

  data_json = jsonencode({
    SSO_OIDC_CLIENT_ID     = module.oidc.client_id
    SSO_OIDC_CLIENT_SECRET = module.oidc.client_secret
  })
}

moved {
  from = random_password.hi_events_client_secret
  to   = module.oidc.random_password.client_secret[0]
}

moved {
  from = authentik_provider_oauth2.hi_events
  to   = module.oidc.authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.hi_events
  to   = module.oidc.authentik_application.application
}
