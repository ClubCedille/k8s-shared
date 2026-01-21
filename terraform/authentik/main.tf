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

# # Fetch all groups
# data "authentik_groups" "all" {
#   slug = ""
# }

# # Create generic exec role + group and bind them together
# resource "authentik_group" "exec" {
#   name         = "exec-test"
#   is_superuser = false
#   roles = ["exec-test"]
# }

# resource "authentik_group" "club" {
#   name         = "exec-test"
#   is_superuser = false
#   roles = ["club-test"]
# }

# resource "authentik_rbac_role" "my-role" {
#   name = "my-role"
# }

# resource "authentik_rbac_permission_role" "global-permission" {
#   role       = authentik_rbac_role.my-role.id
#   model      = "authentik_flows.flow"
#   permission = "inspect_flow"
#   object_id  = authentik_flow.flow.uuid
# }
# authentik Core
# - Can view Group
# - Can view User
# authentik RBAC
# - Can access admin interface

# Permissions d'objet assignés
# Can view Group 	        Group club-[]
# Remove user from group 	Group club-[]
# Add user to group 	    Group club-[]
# Can view Group 	        Group exec-[]
# Remove user from group 	Group exec-[]
# Add user to group 	    Group exec-[]

# Permissions

# data "authentik_rbac_permission" "can_view_group" {
#   codename = "Can view Group"
# }

# data "authentik_rbac_permission" "can_view_user" {
#   codename = "Can view User"
# }

# data "authentik_rbac_permission" "can_access_admin_interface" {
#   codename = "Can access admin interface"
# }

# resource "authentik_rbac_initial_permissions" "exec_permissions" {
#   name = "exec-template"
#   permissions = tolist([
#     data.authentik_rbac_permission.can_view_user.id,
#     data.authentik_rbac_permission.can_view_group.id,
#     data.authentik_rbac_permission.can_access_admin_interface.id ])
#   role = "exec-template"
#   mode = "role"
# }

# resource "authentik_rbac_initial_permissions" "club_permissions" {
#   name = "club-template"
#   permissions = tolist([
#     data.authentik_rbac_permission.can_view_user.id,
#     data.authentik_rbac_permission.can_view_group.id,
#     data.authentik_rbac_permission.can_access_admin_interface.id ])
#   role = "club-template"
#   mode = "role"
# }
