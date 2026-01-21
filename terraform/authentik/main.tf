# Set Brand config
resource "authentik_brand" "authentik-test" {
  domain         = "."
  default        = true
  branding_title = "CEDILLE-TEST"
  branding_favicon = "/static/dist/assets/icons/icon.png"
  branding_logo = "/media/custom/branding/Logo_text_white.png"
  flow_authentication = "default-authentication-flow" # (String)
  flow_invalidation = "default-invalidation-flow" # (String)
  flow_user_settings = "default-user-settings-flow" # (String)
  attributes = jsonencode({
    settings = {
      theme = {
        base = "dark"
      },
      locale = "fr_CA"
    }
  })

  # branding_default_flow_background = "" # (String) Defaults to /static/dist/assets/images/flow_background.jpg.
  # branding_custom_css = "" # (String)
  # client_certificates = "" # (List of String)
  # default_application = "" # (String)
  # flow_device_code = "" # (String)
  # flow_recovery = "" # (String)
  # flow_unenrollment = "" # (String)
  # web_certificate = "" # (String)

}
