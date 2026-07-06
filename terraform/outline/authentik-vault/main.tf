terraform {
  required_version = ">=1.14"
  backend "kubernetes" {
    secret_suffix    = "state-outlinewiki"
    namespace        = "terraform"
    config_path      = "~/.kube/config"
  }

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2025.12.1"
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
  address = "https://vault.etsmtl.club"
}

locals {
  clubs = jsondecode(file("${path.module}/clubs.json"))
}

resource "random_password" "outline_client_secret" {
  for_each = toset(local.clubs)

  length           = 48
  special          = true
  override_special = "!-_="
}

resource "random_id" "outline_secret_key" {
  for_each    = toset(local.clubs)
  byte_length = 32
}

resource "random_id" "outline_utils_secret" {
  for_each    = toset(local.clubs)
  byte_length = 32
}

resource "vault_kv_secret" "outline-secrets" {
  for_each = toset(local.clubs)

  path = "kv/data/${each.key}-outlinewiki/default/outline-secrets"

  data_json = jsonencode({
    OIDC_CLIENT_ID     = authentik_provider_oauth2.outline_provider[each.key].client_id
    OIDC_CLIENT_SECRET = authentik_provider_oauth2.outline_provider[each.key].client_secret
    SECRET_KEY         = random_id.outline_secret_key[each.key].hex
    UTILS_SECRET       = random_id.outline_utils_secret[each.key].hex
    DATABASE_URL       = "postgres://${var.db_user}:${var.db_password}@postgresql-outline-${each.key}-rw.${each.key}-outlinewiki.svc.cluster.local:5432/outline"
  })
}

resource "vault_kv_secret" "outline-postgresql" {
  for_each = toset(local.clubs)

  path = "kv/data/${each.key}-outlinewiki/default/outline-postgresql"

  data_json = jsonencode({
    username = var.db_user
    password = var.db_password
  })
}

data "authentik_flow" "default-authorization-flow" {
  slug = "default-provider-authorization-explicit-consent"
}

data "authentik_flow" "default-invalidation-flow" {
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

resource "authentik_provider_oauth2" "outline_provider" {
  for_each = toset(local.clubs)

  name               = "outlinewiki-${each.key}"
  client_id          = "outlinewiki-${each.key}"
  client_secret      = random_password.outline_client_secret[each.key].result
  authorization_flow = data.authentik_flow.default-authorization-flow.id
  invalidation_flow  = data.authentik_flow.default-invalidation-flow.id
  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]
  allowed_redirect_uris = [
    {
      "matching_mode" = "strict"
      "url"           = "https://wiki.${each.key}.etsmtl.club/auth/oidc.callback"
    },
  ]
}

resource "authentik_application" "outline_app" {
  for_each = toset(local.clubs)

  name              = "Wiki ${each.key}"
  slug              = "outlinewiki-${each.key}"
  protocol_provider = authentik_provider_oauth2.outline_provider[each.key].id
}
