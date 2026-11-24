terraform {
  required_version = ">=1.14"

  backend "kubernetes" {
    secret_suffix = "state-policy-reporter"
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
  app_slug     = "policy-reporter"
  app_name     = "Policy Reporter"
  namespace    = "policy-reporter"
  hostname     = "policy-reporter.etsmtl.club"
  vault_secret = "kv/data/${local.namespace}/default/policy-reporter-oidc-secret"
}

# Seuls les membres de ce groupe peuvent atteindre l'UI externe -- la
# liaison est appliquee au niveau applicatif Authentik
# (authentik_policy_binding), pas seulement cote UI.
resource "authentik_group" "policy_reporter_users" {
  name = "policy-reporter-users"
}

module "oidc" {
  source = "../../modules/oidc-app"

  app_slug            = local.app_slug
  app_name            = local.app_name
  grant_types         = ["authorization_code", "refresh_token"]
  signing_key_name    = "authentik Self-signed Certificate"
  create_groups_scope = true

  access_token_validity  = "hours=12"
  refresh_token_validity = "days=30"

  access_group_id = authentik_group.policy_reporter_users.id

  redirect_uris = [
    {
      url = "https://${local.hostname}/callback"
    },
  ]
}

resource "vault_kv_secret" "policy_reporter_oidc_secret" {
  path = local.vault_secret

  # Cles attendues par l'UI Policy Reporter ("openIDConnect.secretRef") :
  # discoveryUrl, clientId, clientSecret.
  data_json = jsonencode({
    discoveryUrl = "https://auth.etsmtl.club/application/o/${local.app_slug}/.well-known/openid-configuration"
    clientId     = module.oidc.client_id
    clientSecret = module.oidc.client_secret
  })
}

moved {
  from = random_password.policy_reporter_client_secret
  to   = module.oidc.random_password.client_secret[0]
}

moved {
  from = authentik_property_mapping_provider_scope.groups
  to   = module.oidc.authentik_property_mapping_provider_scope.groups[0]
}

moved {
  from = authentik_provider_oauth2.policy_reporter
  to   = module.oidc.authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.policy_reporter
  to   = module.oidc.authentik_application.application
}

moved {
  from = authentik_policy_binding.policy_reporter_access
  to   = module.oidc.authentik_policy_binding.access[0]
}
