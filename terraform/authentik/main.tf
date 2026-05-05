# Set Brand config
resource "authentik_brand" "authentik-test" {
  domain         = "authentik-test"
  default        = false
  branding_title = "CEDILLE-TEST-VRAI"
  branding_favicon = "/static/dist/assets/icons/icon.png"
  branding_logo = "/media/custom/branding/Logo_text_white.png"
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
