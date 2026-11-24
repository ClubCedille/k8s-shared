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

# Membership in these groups grants the Grafana "Editor" role (dashboard
# creation + Explore/Drilldown) on next login, via role_attribute_path in
# apps/grafana/helm/values.yaml. They are created by terraform/authentik;
# this root only manages the Lan_ETS-specific groups below.
removed {
  from = authentik_group.grafana_dashboard_creators
  lifecycle {
    destroy = false
  }
}

removed {
  from = authentik_group.grafana_metrics_explorers
  lifecycle {
    destroy = false
  }
}

# Ces trois groupes ne donnent pas un role dans l'org par defaut (Cedille)
# mais l'acces a l'org separee "Lan_ETS" : org_mapping dans
# apps/grafana/helm/values.yaml les mappe vers Admin/Editor/Viewer dans
# cette org au prochain login OIDC.
resource "authentik_group" "grafana_lanets_admin" {
  name = "grafana-lanets-admin"
}

resource "authentik_group" "grafana_lanets_editor" {
  name = "grafana-lanets-editor"
}

resource "authentik_group" "grafana_lanets_viewer" {
  name = "grafana-lanets-viewer"
}

module "oidc" {
  source = "../../modules/oidc-app"

  app_slug            = local.app_slug
  app_name            = local.app_name
  grant_types         = ["authorization_code", "refresh_token"]
  create_groups_scope = true

  redirect_uris = [
    {
      url = "https://${local.hostname}/login/generic_oauth"
    },
  ]
}

resource "vault_kv_secret" "grafana_oidc_secret" {
  path = local.vault_secret

  data_json = jsonencode({
    OIDC_CLIENT_ID     = module.oidc.client_id
    OIDC_CLIENT_SECRET = module.oidc.client_secret
  })
}

moved {
  from = random_password.grafana_client_secret
  to   = module.oidc.random_password.client_secret[0]
}

moved {
  from = authentik_property_mapping_provider_scope.groups
  to   = module.oidc.authentik_property_mapping_provider_scope.groups[0]
}

moved {
  from = authentik_provider_oauth2.grafana
  to   = module.oidc.authentik_provider_oauth2.provider
}

moved {
  from = authentik_application.grafana
  to   = module.oidc.authentik_application.application
}
