#https://registry.terraform.io/providers/goauthentik/authentik/latest/docs
# Set Brand config
resource "authentik_brand" "authentik-test" {
  domain           = "authentik-test"
  default          = false
  branding_title   = "CEDILLE-TEST-VRAI"
  branding_favicon = "/static/dist/assets/icons/icon.png"
  branding_logo    = "/media/custom/branding/Logo_text_white.png"
  attributes = jsonencode({
    settings = {
      theme = {
        base = "dark"
      },
      locale = "fr_CA"
    }
  })

  # flow_invalidation = "default-invalidation-flow" # (String)
  # flow_authentication = "default-authentication-flow" # (String)
  # flow_user_settings = "default-user-settings-flow" # (String)
  # branding_default_flow_background = "" # (String) Defaults to /static/dist/assets/images/flow_background.jpg.
  # branding_custom_css = "" # (String)
  # client_certificates = "" # (List of String)
  # default_application = "" # (String)
  # flow_device_code = "" # (String)
  # flow_recovery = "" # (String)
  # flow_unenrollment = "" # (String)
  # web_certificate = "" # (String)

}

# Authentik ne pose `email_verified: true` que si la vérification par
# courriel est explicitement configurée dans le flow d'un provider -- ce qui
# n'est le cas pour aucune de nos apps. Plusieurs clients OIDC (Coder,
# potentiellement d'autres à l'avenir) rejettent ou avertissent si ce claim
# est absent/false. Ce scope mapping partagé remplace le mapping "email"
# managé par défaut : à référencer par nom (data source) dans les modules
# terraform/*/authentik-vault plutôt que de contourner le problème côté
# client (ex: CODER_OIDC_IGNORE_EMAIL_VERIFIED).
resource "authentik_property_mapping_provider_scope" "email_verified" {
  name       = "cedille-scope-email-verified"
  scope_name = "email"
  expression = "return {\"email\": user.email, \"email_verified\": True}"
}
