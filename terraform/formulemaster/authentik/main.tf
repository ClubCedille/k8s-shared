terraform {
  required_version = ">=1.14"

  backend "kubernetes" {
    secret_suffix = "state-formulemaster-authentik"
    namespace     = "terraform"
    config_path   = "~/.kube/config"
  }

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "2025.12.1"
    }
  }
}

variable "AUTHENTIK_API_TOKEN" {
  type      = string
  sensitive = true
}

provider "authentik" {
  url   = "https://auth.etsmtl.club"
  token = var.AUTHENTIK_API_TOKEN
}

locals {
  formulemaster_groups = [
    "formulemaster-capitaines",
    "formulemaster-gestionnaires-beton",
    "formulemaster-users",
  ]
}

data "authentik_group" "formulemaster" {
  for_each = toset(local.formulemaster_groups)
  name     = each.key
}

data "authentik_flow" "formulemaster_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "formulemaster_invalidation" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_outpost" "formulemaster_embedded" {
  name = "authentik Embedded Outpost"
}

resource "authentik_provider_proxy" "formulemaster" {
  name                  = "FormuleMaster"
  mode                  = "proxy"
  external_host         = "https://formule.canoe.etsmtl.club"
  internal_host         = "http://formulemaster.formulemaster.svc.cluster.local:3000"
  authorization_flow    = data.authentik_flow.formulemaster_authorization.id
  invalidation_flow     = data.authentik_flow.formulemaster_invalidation.id
  intercept_header_auth = false
}

resource "authentik_application" "formulemaster" {
  name               = "FormuleMaster"
  slug               = "formulemaster"
  protocol_provider  = authentik_provider_proxy.formulemaster.id
  policy_engine_mode = "any"
}

resource "authentik_policy_binding" "formulemaster" {
  for_each = data.authentik_group.formulemaster

  target = authentik_application.formulemaster.uuid
  group  = each.value.id
  order  = index(local.formulemaster_groups, each.key)
}

resource "authentik_outpost_provider_attachment" "formulemaster" {
  outpost           = data.authentik_outpost.formulemaster_embedded.id
  protocol_provider = authentik_provider_proxy.formulemaster.id

  # Le proxy n'accepte les requêtes qu'après la configuration des groupes autorisés.
  depends_on = [authentik_policy_binding.formulemaster]
}
