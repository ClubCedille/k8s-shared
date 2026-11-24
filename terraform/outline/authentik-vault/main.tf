terraform {
  required_version = ">=1.14"

  backend "kubernetes" {
    secret_suffix = "state-outlinewiki"
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
  clubs = jsondecode(file("${path.module}/clubs.json"))

  # Les noms affiches ont ete personnalises dans l'interface Authentik ;
  # on les fige ici pour que le refactor ne les renomme pas en "Wiki <club>".
  app_names = {
    capra   = "Wiki Capra"
    conjure = "Wiki Conjure"
    dci     = "Wiki DCI"
    piranha = "Wiki Frat"
  }
}

resource "random_id" "outline_secret_key" {
  for_each    = toset(local.clubs)
  byte_length = 32
}

resource "random_id" "outline_utils_secret" {
  for_each    = toset(local.clubs)
  byte_length = 32
}

data "authentik_property_mapping_provider_scope" "offline_access" {
  managed = "goauthentik.io/providers/oauth2/scope-offline_access"
}

module "oidc" {
  source   = "../../modules/oidc-app"
  for_each = toset(local.clubs)

  app_slug                = "outlinewiki-${each.key}"
  app_name                = "Wiki ${each.key}"
  application_name        = lookup(local.app_names, each.key, "Wiki ${each.key}")
  grant_types             = ["authorization_code", "refresh_token"]
  use_default_email_scope = true

  extra_property_mapping_ids = [
    data.authentik_property_mapping_provider_scope.offline_access.id,
  ]

  redirect_uris = [
    {
      url = "https://wiki.${each.key}.etsmtl.club/auth/oidc.callback"
    },
  ]
}

resource "vault_kv_secret" "outline-secrets" {
  for_each = toset(local.clubs)

  path = "kv/data/${each.key}-outlinewiki/default/outline-secrets"

  data_json = jsonencode({
    OIDC_CLIENT_ID     = module.oidc[each.key].client_id
    OIDC_CLIENT_SECRET = module.oidc[each.key].client_secret
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

moved {
  from = random_password.outline_client_secret["capra"]
  to   = module.oidc["capra"].random_password.client_secret[0]
}

moved {
  from = authentik_provider_oauth2.outline_provider["capra"]
  to   = module.oidc["capra"].authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.outline_app["capra"]
  to   = module.oidc["capra"].authentik_application.application
}

moved {
  from = random_password.outline_client_secret["conjure"]
  to   = module.oidc["conjure"].random_password.client_secret[0]
}

moved {
  from = authentik_provider_oauth2.outline_provider["conjure"]
  to   = module.oidc["conjure"].authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.outline_app["conjure"]
  to   = module.oidc["conjure"].authentik_application.application
}

moved {
  from = random_password.outline_client_secret["dci"]
  to   = module.oidc["dci"].random_password.client_secret[0]
}

moved {
  from = authentik_provider_oauth2.outline_provider["dci"]
  to   = module.oidc["dci"].authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.outline_app["dci"]
  to   = module.oidc["dci"].authentik_application.application
}

moved {
  from = random_password.outline_client_secret["piranha"]
  to   = module.oidc["piranha"].random_password.client_secret[0]
}

moved {
  from = authentik_provider_oauth2.outline_provider["piranha"]
  to   = module.oidc["piranha"].authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.outline_app["piranha"]
  to   = module.oidc["piranha"].authentik_application.application
}
