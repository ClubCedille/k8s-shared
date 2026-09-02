terraform {
  required_version = ">=1.14"
  backend "kubernetes" {
    secret_suffix = "state-grafana"
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
  app_slug = "grafana"
  app_name = "Grafana"
  hostname = "grafana.etsmtl.club"
  # secret-reader's Vault policy scopes reads to kv/data/<namespace>/
  # <service_account_name>/* -- Grafana runs in namespace "monitoring"
  # (not "grafana") with serviceAccount: default (confirmed live: 403
  # permission denied with the wrong namespace segment).
  vault_secret = "kv/data/monitoring/default/grafana-oidc-secret"
}

# Membership in either group grants the Grafana "Editor" role (dashboard
# creation + Explore/Drilldown) on next login, via role_attribute_path in
# apps/grafana/helm/values.yaml. Kept as two separate groups rather than
# one, even though they currently grant the same Grafana role -- Grafana
# OSS has no Team Sync (Enterprise-only, confirmed against Grafana's own
# docs), so a finer-grained "Explore only, no dashboard editing" tier
# isn't achievable without either paying for Enterprise or standing up a
# custom sync job; splitting the groups now means membership is already
# tracked separately if/when one of those becomes worth doing.
resource "authentik_group" "grafana_dashboard_creators" {
  name = "grafana-dashboard-creators"
}

resource "authentik_group" "grafana_metrics_explorers" {
  name = "grafana-metrics-explorers"
}

resource "random_password" "grafana_client_secret" {
  length           = 48
  special          = true
  override_special = "!-_="
}

resource "vault_kv_secret" "grafana_oidc_secret" {
  path = local.vault_secret

  data_json = jsonencode({
    OIDC_CLIENT_ID     = authentik_provider_oauth2.grafana.client_id
    OIDC_CLIENT_SECRET = authentik_provider_oauth2.grafana.client_secret
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

# The default-managed "email" mapping doesn't set email_verified: true (no
# email verification flow configured) -- reuse the shared mapping from
# terraform/authentik/main.tf like terraform/coder/authentik-vault does.
data "authentik_property_mapping_provider_scope" "email" {
  name = "cedille-scope-email-verified"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

# None of the existing apps expose the "groups" claim except Coder's own
# provider-specific mapping (terraform/coder/authentik-vault) -- property
# mappings are attached per-provider in Authentik, so Grafana needs its
# own copy of the same expression rather than reusing Coder's.
resource "authentik_property_mapping_provider_scope" "groups" {
  name       = "grafana-scope-groups"
  scope_name = "groups"
  expression = "return {\"groups\": [group.name for group in user.ak_groups.all()]}"
}

resource "authentik_provider_oauth2" "grafana" {
  name               = local.app_slug
  client_id          = local.app_slug
  client_secret      = random_password.grafana_client_secret.result
  grant_types        = ["authorization_code", "refresh_token"]
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
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
      url               = "https://${local.hostname}/login/generic_oauth"
    },
  ]
}

resource "authentik_application" "grafana" {
  name              = local.app_name
  slug              = local.app_slug
  protocol_provider = authentik_provider_oauth2.grafana.id
}
