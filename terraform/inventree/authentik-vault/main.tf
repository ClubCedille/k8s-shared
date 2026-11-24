terraform {
  required_version = ">=1.14"

  backend "kubernetes" {
    secret_suffix = "state-inventree"
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
  app_slug          = "inventree"
  app_name          = "InvenTree"
  access_group      = "club-comets"
  namespace         = "comets-inventree"
  hostname          = "inventree.prodv2.cedille.club"
  issuer_url        = "https://auth.etsmtl.club/application/o/${local.app_slug}/"
  sso_secret_path   = "kv/data/${local.namespace}/default/inventree-sso"
  admin_secret_path = "kv/data/${local.namespace}/default/inventree-admin"
}

resource "random_password" "inventree_admin_password" {
  length           = 32
  special          = true
  override_special = "!-_="
}

resource "vault_kv_secret" "inventree_admin" {
  path = local.admin_secret_path

  data_json = jsonencode({
    INVENTREE_ADMIN_USER     = "admin"
    INVENTREE_ADMIN_PASSWORD = random_password.inventree_admin_password.result
    INVENTREE_ADMIN_EMAIL    = var.INVENTREE_ADMIN_EMAIL
  })
}

data "authentik_group" "comets" {
  name          = local.access_group
  include_users = false
}

module "oidc" {
  source = "../../modules/oidc-app"

  app_slug         = local.app_slug
  app_name         = local.app_name
  grant_types      = ["authorization_code", "refresh_token"]
  signing_key_name = "authentik Self-signed Certificate"

  access_group_id = data.authentik_group.comets.id

  meta_launch_url = "https://${local.hostname}"
  open_in_new_tab = true

  redirect_uris = [
    {
      url = "https://${local.hostname}/accounts/authentik/login/callback/"
    },
  ]
}

resource "vault_kv_secret" "inventree_sso" {
  path = local.sso_secret_path

  data_json = jsonencode({
    providers = jsonencode({
      openid_connect = {
        APPS = [
          {
            provider_id = "authentik"
            name        = "Authentik"
            client_id   = module.oidc.client_id
            secret      = module.oidc.client_secret

            settings = {
              server_url         = local.issuer_url
              fetch_userinfo     = true
              oauth_pkce_enabled = true
            }
          },
        ]
      }
    })
  })
}

moved {
  from = random_password.inventree_client_secret
  to   = module.oidc.random_password.client_secret[0]
}

moved {
  from = authentik_provider_oauth2.inventree
  to   = module.oidc.authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.inventree
  to   = module.oidc.authentik_application.application
}

moved {
  from = authentik_policy_binding.inventree_comets_access
  to   = module.oidc.authentik_policy_binding.access[0]
}
