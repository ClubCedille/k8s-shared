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
