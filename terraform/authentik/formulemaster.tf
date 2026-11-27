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
  for_each = {
    capitaines = {
      group = authentik_group.formulemaster_capitaines.id
      order = 0
    }
    gestionnaires_beton = {
      group = authentik_group.formulemaster_gestionnaires_beton.id
      order = 1
    }
    users = {
      group = authentik_group.formulemaster_users.id
      order = 2
    }
  }

  target = authentik_application.formulemaster.uuid
  group  = each.value.group
  order  = each.value.order
}

resource "authentik_outpost_provider_attachment" "formulemaster" {
  outpost           = data.authentik_outpost.formulemaster_embedded.id
  protocol_provider = authentik_provider_proxy.formulemaster.id

  # Le proxy n'accepte les requêtes qu'après la configuration des groupes autorisés.
  depends_on = [authentik_policy_binding.formulemaster]
}
