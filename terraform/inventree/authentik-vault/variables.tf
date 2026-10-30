variable "AUTHENTIK_API_TOKEN" {
  type      = string
  sensitive = true
}

variable "INVENTREE_ADMIN_EMAIL" {
  type        = string
  description = "Adresse du compte administrateur local initial"
}