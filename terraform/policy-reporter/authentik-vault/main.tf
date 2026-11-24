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

resource "random_password" "policy_reporter_client_secret" {
  length           = 48
  special          = true
  override_special = "!-_="
}

resource "vault_kv_secret" "policy_reporter_oidc_secret" {
  path = local.vault_secret

  # Cles attendues par l'UI Policy Reporter ("openIDConnect.secretRef") :
  # discoveryUrl, clientId, clientSecret.
  data_json = jsonencode({
    discoveryUrl = "https://auth.etsmtl.club/application/o/${local.app_slug}/.well-known/openid-configuration"
    clientId     = authentik_provider_oauth2.policy_reporter.client_id
    clientSecret = authentik_provider_oauth2.policy_reporter.client_secret
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

# Le mapping "email" manage par defaut d'Authentik ne pose pas
# email_verified: true (pas de flow de verification courriel) -- reutilise le
# mapping partage de terraform/authentik/main.tf comme les autres apps.
data "authentik_property_mapping_provider_scope" "email" {
  name = "cedille-scope-email-verified"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

# Les property mappings sont rattachees par-provider : Policy Reporter a
# besoin de sa propre copie (les membres du groupe policy-reporter-users
# sont attribues via le claim "groups", groupClaim dans le config UI).
resource "authentik_property_mapping_provider_scope" "groups" {
  name       = "policy-reporter-scope-groups"
  scope_name = "groups"
  expression = "return {\"groups\": [group.name for group in user.ak_groups.all()]}"
}

# Authentik signe l'id_token en HS256 si `signing_key` n'est pas defini.
# Le backend OIDC du UI (goth) ne valide pas HS256 de maniere symetrique --
# force la signature RS256 avec le certificat auto-signe de l'instance.
data "authentik_certificate_key_pair" "default" {
  name = "authentik Self-signed Certificate"
}

resource "authentik_provider_oauth2" "policy_reporter" {
  name               = local.app_slug
  client_id          = local.app_slug
  client_secret      = random_password.policy_reporter_client_secret.result
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
  allowed_redirect_uris = [
    {
      matching_mode     = "strict"
      redirect_uri_type = "authorization"
      url               = "https://${local.hostname}/callback"
    },
  ]
}

resource "authentik_application" "policy_reporter" {
  name              = local.app_name
  slug              = local.app_slug
  protocol_provider = authentik_provider_oauth2.policy_reporter.id
  meta_icon         = "https://media.licdn.com/dms/image/v2/D4E0BAQFLkmuLbRcEQg/company-logo_200_200/company-logo_200_200/0/1720637147139/policyreporter1_logo?e=2147483647&v=beta&t=2Tdn-Kb3p4cttuq-XRcV6z8zJ-H7pRtPLBtW68qY1yc"
  # The portal folder is managed manually in Authentik.
  lifecycle {
    ignore_changes = [group]
  }
}

resource "authentik_policy_binding" "policy_reporter_access" {
  target = authentik_application.policy_reporter.uuid
  group  = authentik_group.policy_reporter_users.id
  order  = 0
}
