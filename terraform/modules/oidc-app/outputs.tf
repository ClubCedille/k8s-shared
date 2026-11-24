output "client_id" {
  value       = authentik_provider_oauth2.provider.client_id
  description = "Client ID OAuth2 du provider."
}

output "client_secret" {
  value       = var.client_type == "public" ? null : random_password.client_secret[0].result
  description = "Client secret OAuth2 (null pour un client public)."
  sensitive   = true
}

output "provider_id" {
  value       = authentik_provider_oauth2.provider.id
  description = "ID du provider OAuth2 Authentik."
}

output "application_uuid" {
  value       = authentik_application.application.uuid
  description = "UUID de l'application Authentik."
}
