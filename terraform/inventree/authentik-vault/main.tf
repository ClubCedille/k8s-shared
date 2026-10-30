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

resource "random_password" "inventree_client_secret" {
    length = 48
    special = true
    override_special = "!-_="
}

resource "random_password" "inventree_admin_password" {
    length = 32
    special = true
    override_special = "!-_="
}

resource "vault_kv_secret" "inventree_admin" {
    path = local.admin_secret_path
    data_json = jsonencode({
        INVENTREE_ADMIN_USER = "admin"
        INVENTREE_ADMIN_PASSWORD = random_password.inventree_admin_password.result
        INVENTREE_ADMIN_EMAIL = var.INVENTREE_ADMIN_EMAIL
    })
}

data "authentik_flow" "default_authorization_flow" {
  slug = "default-provider-authorization-explicit-consent"
}

data "authentik_flow" "default_invalidation_flow" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_property_mapping_provider_scope" "openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_property_mapping_provider_scope" "email" {
  name = "cedille-scope-email-verified"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

data "authentik_group" "comets" {
  name          = local.access_group
  include_users = false
}
