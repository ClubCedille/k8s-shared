terraform {
  required_version = ">=1.14"

  backend "kubernetes" {
    secret_suffix = "state-dci-nodered"
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
  app_slug     = "dci-summercamp-nodered"
  app_name     = "Node-RED DCI Summercamp"
  access_group = "summercamp"
  namespace    = "dci-nodered"
  hostname     = "nodered-summercamp2026.etsmtl.club"
  vault_secret = "kv/data/${local.namespace}/default/nodered-secrets"
}

resource "random_password" "nodered_credential_secret" {
  length           = 48
  special          = true
  override_special = "!-_="
}

data "authentik_group" "summercamp" {
  name          = local.access_group
  include_users = false
}

module "oidc" {
  source = "../../modules/oidc-app"

  app_slug                = local.app_slug
  app_name                = local.app_name
  grant_types             = ["authorization_code"]
  use_default_email_scope = true

  access_group_id = data.authentik_group.summercamp.id

  redirect_uris = [
    {
      url = "https://${local.hostname}/auth/strategy/callback/"
    },
  ]
}

resource "vault_kv_secret" "nodered_secrets" {
  path = local.vault_secret

  data_json = jsonencode({
    OIDC_CLIENT_ID             = module.oidc.client_id
    OIDC_CLIENT_SECRET         = module.oidc.client_secret
    NODE_RED_CREDENTIAL_SECRET = random_password.nodered_credential_secret.result
  })
}

moved {
  from = random_password.nodered_client_secret
  to   = module.oidc.random_password.client_secret[0]
}

moved {
  from = authentik_provider_oauth2.nodered
  to   = module.oidc.authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.nodered
  to   = module.oidc.authentik_application.application
}

moved {
  from = authentik_policy_binding.nodered_summercamp_access
  to   = module.oidc.authentik_policy_binding.access[0]
}
