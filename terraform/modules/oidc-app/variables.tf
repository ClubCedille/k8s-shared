variable "app_slug" {
  type        = string
  description = "Slug de l'application (aussi utilise pour le nom du provider et le slug de l'application Authentik)."
}

variable "app_name" {
  type        = string
  description = "Nom affiche de l'application Authentik."
}

variable "provider_name" {
  type        = string
  default     = null
  description = "Nom du provider OAuth2. Defaut: app_slug."
}

variable "application_name" {
  type        = string
  default     = null
  description = "Nom de l'application Authentik. Defaut: app_name."
}

variable "client_id" {
  type        = string
  default     = null
  description = "Client ID OAuth2. Defaut: app_slug."
}

variable "client_type" {
  type        = string
  default     = "confidential"
  description = "Type de client OAuth2: confidential (client_secret) ou public (PKCE)."

  validation {
    condition     = contains(["confidential", "public"], var.client_type)
    error_message = "client_type doit etre 'confidential' ou 'public'."
  }
}

variable "grant_types" {
  type        = list(string)
  default     = ["authorization_code"]
  description = "Grant types autorises sur le provider."
}

variable "redirect_uris" {
  type = list(object({
    matching_mode     = optional(string, "strict")
    redirect_uri_type = optional(string, "authorization")
    url               = string
  }))
  description = "URI de redirection autorisees par Authentik."
}

variable "signing_key_name" {
  type        = string
  default     = null
  description = "Nom du certificat Authentik utilise pour signer les tokens (RS256). Defaut: pas de signing key (HS256)."
}

variable "use_default_email_scope" {
  type        = bool
  default     = false
  description = "Utiliser le mapping email manage par Authentik au lieu de cedille-scope-email-verified."
}

variable "create_groups_scope" {
  type        = bool
  default     = false
  description = "Creer un scope mapping 'groups' propre a l'application."
}

variable "groups_scope_name" {
  type        = string
  default     = null
  description = "Nom du scope mapping groups. Defaut: <app_slug>-scope-groups."
}

variable "extra_property_mapping_ids" {
  type        = list(string)
  default     = []
  description = "IDs de scope mappings additionnels a inclure dans le provider."
}

variable "access_group_id" {
  type        = string
  default     = null
  description = "ID du groupe Authentik autorise a acceder a l'application (policy binding). Defaut: aucun binding."
}

variable "access_token_validity" {
  type        = string
  default     = null
  description = "Validite de l'access token (ex: hours=12). Defaut: valeur Authentik."
}

variable "refresh_token_validity" {
  type        = string
  default     = null
  description = "Validite du refresh token (ex: days=30). Defaut: valeur Authentik."
}

variable "meta_launch_url" {
  type        = string
  default     = null
  description = "URL de lancement de l'application dans le portail Authentik."
}

variable "open_in_new_tab" {
  type        = bool
  default     = false
  description = "Ouvrir l'application dans un nouvel onglet depuis le portail Authentik."
}

variable "client_secret_length" {
  type        = number
  default     = 48
  description = "Longueur du client_secret genere (clients confidentiels seulement)."
}

variable "client_secret_override_special" {
  type        = string
  default     = "!-_="
  description = "Caracteres speciaux autorises dans le client_secret genere."
}
