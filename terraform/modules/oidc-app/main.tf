data "authentik_flow" "authorization" {
  slug = "default-provider-authorization-explicit-consent"
}

data "authentik_flow" "invalidation" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_property_mapping_provider_scope" "openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

# Le mapping "email" manage par defaut ne pose pas email_verified: true ; on
# reutilise le mapping partage de terraform/authentik/scopes.tf sauf pour les
# applications qui ont besoin du mapping par defaut d'Authentik.
data "authentik_property_mapping_provider_scope" "email_shared" {
  count = var.use_default_email_scope ? 0 : 1
  name  = "cedille-scope-email-verified"
}

data "authentik_property_mapping_provider_scope" "email_default" {
  count   = var.use_default_email_scope ? 1 : 0
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

data "authentik_certificate_key_pair" "signing" {
  count = var.signing_key_name == null ? 0 : 1
  name  = var.signing_key_name
}

# Les clients publics (SPA avec PKCE) n'ont pas de client_secret.
resource "random_password" "client_secret" {
  count            = var.client_type == "public" ? 0 : 1
  length           = var.client_secret_length
  special          = true
  override_special = var.client_secret_override_special
}

resource "authentik_property_mapping_provider_scope" "groups" {
  count      = var.create_groups_scope ? 1 : 0
  name       = coalesce(var.groups_scope_name, "${var.app_slug}-scope-groups")
  scope_name = "groups"
  expression = "return {\"groups\": [group.name for group in user.ak_groups.all()]}"
}

resource "authentik_provider_oauth2" "provider" {
  name          = coalesce(var.provider_name, var.app_slug)
  client_id     = coalesce(var.client_id, var.app_slug)
  client_type   = var.client_type
  client_secret = var.client_type == "public" ? null : random_password.client_secret[0].result

  grant_types        = var.grant_types
  authorization_flow = data.authentik_flow.authorization.id
  invalidation_flow  = data.authentik_flow.invalidation.id
  signing_key        = var.signing_key_name == null ? null : data.authentik_certificate_key_pair.signing[0].id

  access_token_validity  = var.access_token_validity
  refresh_token_validity = var.refresh_token_validity

  property_mappings = concat(
    [
      data.authentik_property_mapping_provider_scope.openid.id,
      var.use_default_email_scope ? data.authentik_property_mapping_provider_scope.email_default[0].id : data.authentik_property_mapping_provider_scope.email_shared[0].id,
      data.authentik_property_mapping_provider_scope.profile.id,
    ],
    var.create_groups_scope ? [authentik_property_mapping_provider_scope.groups[0].id] : [],
    var.extra_property_mapping_ids,
  )

  allowed_redirect_uris = var.redirect_uris
}

resource "authentik_application" "application" {
  name              = coalesce(var.application_name, var.app_name)
  slug              = var.app_slug
  protocol_provider = authentik_provider_oauth2.provider.id
  meta_launch_url   = var.meta_launch_url
  open_in_new_tab   = var.open_in_new_tab
}

resource "authentik_policy_binding" "access" {
  count  = var.access_group_id == null ? 0 : 1
  target = authentik_application.application.uuid
  group  = var.access_group_id
  order  = 0
}
