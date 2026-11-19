variable "GRAFANA_SERVICE_ACCOUNT_TOKEN" {
  type      = string
  sensitive = true
}

# Basic auth "admin:<password>" du compte Grafana Server Admin. Requis par
# les ressources grafana_organization (instance-scoped) : un token de
# service account est org-scoped et ne peut ni créer ni renommer d'org.
# À fournir au moment du apply (TF_VAR_GRAFANA_ADMIN_AUTH), idéalement
# lu depuis Vault -- voir docs/grafana-orgs-2026-11/README.md.
variable "GRAFANA_ADMIN_AUTH" {
  type      = string
  sensitive = true
}
