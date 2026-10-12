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

resource "random_password" "penpot_client_secret" {
  length           = 48
  special          = true
  override_special = "!-_="
}

resource "vault_kv_secret" "penpot_oidc_secret" {
  path = local.vault_secret

  data_json = jsonencode({
    OIDC_CLIENT_ID     = authentik_provider_oauth2.penpot.client_id
    OIDC_CLIENT_SECRET = authentik_provider_oauth2.penpot.client_secret
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

# Le mapping "email" managé par défaut d'Authentik ne pose pas
# email_verified: true (aucune vérification par courriel configurée dans nos
# flows) -- on réutilise le mapping partagé de terraform/authentik/scopes.tf.
data "authentik_property_mapping_provider_scope" "email" {
  name = "cedille-scope-email-verified"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

# Penpot valide la signature de l'id_token via le JWKS -- Authentik signe en
# HS256 (symétrique) si `signing_key` n'est pas défini, ce que le JWKS ne peut
# pas exposer. On force RS256 avec le certificat auto-signé d'Authentik, comme
# pour Coder.
data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

resource "authentik_provider_oauth2" "penpot" {
  name               = local.app_slug
  client_id          = local.app_slug
  client_secret      = random_password.penpot_client_secret.result
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
      url               = "https://${local.hostname}/api/auth/oidc/callback"
    },
  ]
}

resource "authentik_application" "penpot" {
  name              = local.app_name
  slug              = local.app_slug
  protocol_provider = authentik_provider_oauth2.penpot.id
}
