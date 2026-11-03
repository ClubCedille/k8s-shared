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

resource "random_password" "hi_events_client_secret" {
  length           = 48
  special          = true
  override_special = "!-_="
}

resource "vault_kv_secret" "hi_events_oidc_secret" {
  path = local.vault_secret

  data_json = jsonencode({
    SSO_OIDC_CLIENT_ID     = authentik_provider_oauth2.hi_events.client_id
    SSO_OIDC_CLIENT_SECRET = authentik_provider_oauth2.hi_events.client_secret
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

# RS256 : id_token validé via JWKS.
data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

resource "authentik_provider_oauth2" "hi_events" {
  name               = local.app_slug
  client_id          = local.app_slug
  client_secret      = random_password.hi_events_client_secret.result
  grant_types        = ["authorization_code", "refresh_token"]
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  signing_key        = data.authentik_certificate_key_pair.default.id
  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]
  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://${local.hostname}/sso/callback"
    },
  ]
}

resource "authentik_application" "hi_events" {
  name              = local.app_name
  slug              = local.app_slug
  protocol_provider = authentik_provider_oauth2.hi_events.id
}
