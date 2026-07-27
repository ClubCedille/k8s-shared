terraform {
  required_version = ">=1.14"
  backend "kubernetes" {
    secret_suffix = "state-coder"
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
  app_slug     = "coder"
  app_name     = "Coder"
  namespace    = "coder"
  hostname     = "coder.etsmtl.club"
  vault_secret = "kv/data/${local.namespace}/default/coder-oidc-secret"
}

resource "random_password" "coder_client_secret" {
  length           = 48
  special          = true
  override_special = "!-_="
}

resource "vault_kv_secret" "coder_oidc_secret" {
  path = local.vault_secret

  data_json = jsonencode({
    OIDC_CLIENT_ID     = authentik_provider_oauth2.coder.client_id
    OIDC_CLIENT_SECRET = authentik_provider_oauth2.coder.client_secret
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

# Aucun des modules existants (outline, nodered) n'expose le claim `groups` --
# Coder en a besoin pour le group sync OIDC (CODER_OIDC_GROUP_FIELD=groups).
resource "authentik_property_mapping_provider_scope" "groups" {
  name       = "coder-scope-groups"
  scope_name = "groups"
  expression = "return {\"groups\": [group.name for group in user.ak_groups.all()]}"
}

# Authentik signe l'id_token en HS256 (symétrique) si `signing_key` n'est pas
# défini. Coder n'accepte que RS256 -- sans ça : "Failed to verify OIDC
# token: unexpected signature algorithm HS256".
data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

resource "authentik_provider_oauth2" "coder" {
  name               = local.app_slug
  client_id          = local.app_slug
  client_secret      = random_password.coder_client_secret.result
  grant_types        = ["authorization_code", "refresh_token"]
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  signing_key        = data.authentik_certificate_key_pair.default.id
  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    authentik_property_mapping_provider_scope.groups.id,
  ]

  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://${local.hostname}/api/v2/users/oidc/callback"
    },
  ]
}

resource "authentik_application" "coder" {
  name              = local.app_name
  slug              = local.app_slug
  protocol_provider = authentik_provider_oauth2.coder.id
}
