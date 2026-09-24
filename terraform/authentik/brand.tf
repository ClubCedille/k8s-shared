# Set Brand config
resource "authentik_brand" "authentik-default" {
  domain                           = "authentik-default"
  default                          = true
  branding_title                   = "CEDILLE"
  branding_favicon                 = "/static/dist/assets/icons/icon_pride_lgbt.png"
  branding_logo                    = "cedille-texte-blanc.png"
  branding_default_flow_background = "/static/dist/assets/images/flow_background.jpg"

  flow_authentication = "5f2f49e6-8319-417b-9493-33b3e66b96b5"
  flow_invalidation   = "91f84c53-ef2d-45d1-9e10-d03ebd776916"
  flow_user_settings  = "8b2f8a18-954f-45c9-ab42-14a1afb75f80"

  attributes = jsonencode({
    settings = {
      theme = {
        base = "dark"
      },
      locale = "fr_CA"
    }
  })
}
