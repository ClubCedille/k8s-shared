# Terraform dependency-track -- provisionne :
#   1. l'application OIDC Authentik (SSO de l'UI Dependency-Track) ;
#   2. les secrets Vault lus par les VaultStaticSecret de apps/dependency-track.
#
# A appliquer AVANT le premier sync ArgoCD de l'app, sinon les secrets
# Kubernetes n'existent pas et les pods restent en attente.
terraform {
  required_version = ">=1.14"
  backend "kubernetes" {
    secret_suffix = "state-dependency-track"
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
  app_slug   = "dependency-track"
  app_name   = "Dependency Track"
  namespace  = "dependency-track"
  hostname   = "dependency-track.etsmtl.club"
  issuer     = "https://auth.etsmtl.club/application/o/dependency-track/"
  vault_base = "kv/data/${local.namespace}/default"
}

#-------------------------------------------------------------------------------
# Secrets consommes par les VaultStaticSecret (role `secret-reader`, scope
# kv/data/<namespace>/<sa>/*).
#-------------------------------------------------------------------------------

resource "random_password" "db_password" {
  length           = 32
  special          = false
}

resource "random_password" "kek" {
  # 32 octets aleatoires, puis base64 : format attendu par
  # secretManagement.database.kek.mode=config de Dependency-Track.
  length           = 32
  special          = false
}

resource "random_password" "oidc_client_secret" {
  length           = 48
  special          = true
  override_special = "!-_="
}

resource "vault_kv_secret" "db_secret" {
  path = "${local.vault_base}/dependency-track-db-secret"

  # Cles username/password : memes cles pour CNPG (basic-auth) et pour
  # database.existingSecret du chart Helm. owner du schema = dtrack (DDL).
  data_json = jsonencode({
    username = "dtrack"
    password = random_password.db_password.result
  })
}

resource "vault_kv_secret" "kek_secret" {
  path = "${local.vault_base}/dependency-track-kek"

  data_json = jsonencode({
    kek = base64encode(random_password.kek.result)
  })
}

resource "vault_kv_secret" "oidc_secret" {
  path = "${local.vault_base}/dependency-track-oidc-secret"

  data_json = jsonencode({
    issuer       = local.issuer
    clientId     = authentik_provider_oauth2.dependency_track.client_id
    clientSecret = authentik_provider_oauth2.dependency_track.client_secret
  })
}

#-------------------------------------------------------------------------------
# SSO Authentik -- client public (PKCE), provisioning des utilisateurs et
# synchronisation des equipes via le claim `groups`.
#-------------------------------------------------------------------------------

resource "authentik_group" "dependency_track_users" {
  name = "dependency-track-users"
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

# Le mapping "email" manage par defaut ne pose pas email_verified: true ;
# on reutilise le mapping partage de terraform/authentik/main.tf.
data "authentik_property_mapping_provider_scope" "email" {
  name = "cedille-scope-email-verified"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

# Dependency-Track lit le claim `groups` pour creer les equipes (team sync).
resource "authentik_property_mapping_provider_scope" "groups" {
  name       = "dependency-track-scope-groups"
  scope_name = "groups"
  expression = "return {\"groups\": [group.name for group in user.ak_groups.all()]}"
}

# RS256 : le backend OIDC de Dependency-Track verifie la signature avec la
# cle publique du provider ; ne pas laisser Authentik signer en HS256.
data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

resource "authentik_provider_oauth2" "dependency_track" {
  name               = local.app_slug
  client_id          = local.app_slug
  client_secret      = random_password.oidc_client_secret.result
  grant_types        = ["authorization_code", "refresh_token"]
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  signing_key        = data.authentik_certificate_key_pair.default.id

  access_token_validity  = "hours=12"
  refresh_token_validity = "days=30"

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    authentik_property_mapping_provider_scope.groups.id,
  ]

  # SPA (code flow + PKCE) : callback a la racine de l'application.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://${local.hostname}"
    },
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://${local.hostname}/"
    },
  ]
}

resource "authentik_application" "dependency_track" {
  name              = local.app_name
  slug              = local.app_slug
  protocol_provider = authentik_provider_oauth2.dependency_track.id
}

resource "authentik_policy_binding" "dependency_track_access" {
  target = authentik_application.dependency_track.uuid
  group  = authentik_group.dependency_track_users.id
  order  = 0
}
