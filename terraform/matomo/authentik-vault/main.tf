terraform {
  required_version = ">=1.14"
  backend "kubernetes" {
    secret_suffix = "state-matomo"
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
  app_slug     = "matomo"
  app_name     = "Matomo"
  namespace    = "matomo"
  hostname     = "matomo.etsmtl.club"
  vault_secret = "kv/data/${local.namespace}/default/matomo-oidc-secret"
}

resource "random_password" "matomo_client_secret" {
  length           = 48
  special          = true
  override_special = "!-_="
}

resource "vault_kv_secret" "matomo_oidc_secret" {
  path = local.vault_secret

  data_json = jsonencode({
    OIDC_CLIENT_ID     = authentik_provider_oauth2.matomo.client_id
    OIDC_CLIENT_SECRET = authentik_provider_oauth2.matomo.client_secret
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
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

resource "authentik_provider_oauth2" "matomo" {
  name               = local.app_slug
  client_id          = local.app_slug
  client_secret      = random_password.matomo_client_secret.result
  grant_types        = ["authorization_code"]
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]

  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://${local.hostname}/index.php?module=LoginOIDC&action=callback&provider=oidc"
    },
  ]
}

resource "authentik_application" "matomo" {
  name              = local.app_name
  slug              = local.app_slug
  protocol_provider = authentik_provider_oauth2.matomo.id
}