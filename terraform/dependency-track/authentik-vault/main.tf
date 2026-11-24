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
  length  = 32
  special = false
}

resource "random_password" "kek" {
  # 32 octets aleatoires, puis base64 : format attendu par
  # secretManagement.database.kek.mode=config de Dependency-Track.
  length  = 32
  special = false
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

#-------------------------------------------------------------------------------
# SSO Authentik -- client public (PKCE), provisioning des utilisateurs et
# synchronisation des equipes via le claim `groups`.
#-------------------------------------------------------------------------------

resource "authentik_group" "dependency_track_users" {
  name = "dependency-track-users"
}

module "oidc" {
  source = "../../modules/oidc-app"

  app_slug    = local.app_slug
  app_name    = local.app_name
  client_type = "public"
  grant_types = ["authorization_code", "refresh_token"]

  # RS256 : le backend OIDC de Dependency-Track verifie la signature avec la
  # cle publique du provider ; ne pas laisser Authentik signer en HS256.
  signing_key_name = "authentik Self-signed Certificate"

  access_token_validity  = "hours=12"
  refresh_token_validity = "days=30"

  # Dependency-Track lit le claim `groups` pour creer les equipes (team sync).
  create_groups_scope = true

  access_group_id = authentik_group.dependency_track_users.id

  # SPA (code flow + PKCE) : le frontend Dependency-Track envoie
  # redirect_uri=https://<host>/static/oidc-callback.html.
  redirect_uris = [
    {
      url = "https://${local.hostname}/static/oidc-callback.html"
    },
  ]
}

resource "vault_kv_secret" "oidc_secret" {
  path = "${local.vault_base}/dependency-track-oidc-secret"

  # Le frontend Dependency-Track est un SPA public (code flow + PKCE) : il
  # n'envoie que client_id au token endpoint. Aucun clientSecret n'est requis
  # ni utilise ; le secret Vault ne contient donc que l'issuer et le clientId.
  data_json = jsonencode({
    issuer   = local.issuer
    clientId = module.oidc.client_id
  })
}

moved {
  from = authentik_property_mapping_provider_scope.groups
  to   = module.oidc.authentik_property_mapping_provider_scope.groups[0]
}

moved {
  from = authentik_provider_oauth2.dependency_track
  to   = module.oidc.authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.dependency_track
  to   = module.oidc.authentik_application.application
}

moved {
  from = authentik_policy_binding.dependency_track_access
  to   = module.oidc.authentik_policy_binding.access[0]
}
