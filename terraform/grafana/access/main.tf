terraform {
  required_version = ">=1.14"
  backend "kubernetes" {
    secret_suffix = "state-grafana-access"
    namespace     = "terraform"
    config_path   = "~/.kube/config"
  }

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "3.25.3"
    }
  }
}

# Auth via un token de service account créé une fois manuellement dans
# Grafana (Administration > Service accounts, rôle Admin) -- il n'existe pas
# de chemin de bootstrap depuis l'OIDC Authentik pour ça, et les ressources
# grafana_service_account/_service_account_token du provider auraient
# elles-mêmes besoin d'un token existant pour s'authentifier. Voir
# variables.tf.
provider "grafana" {
  url  = "https://grafana.etsmtl.club"
  auth = var.GRAFANA_SERVICE_ACCOUNT_TOKEN
}

# Les ressources grafana_organization sont instance-scoped et utilisent
# les API admin de Grafana : un token de service account (org-scoped) ne
# suffit pas, il faut la basic auth du compte Server Admin local. Ce
# provider ne sert qu'aux deux orgs ; les ressources d'org restent sur le
# provider par défaut.
provider "grafana" {
  alias = "admin"
  url   = "https://grafana.etsmtl.club"
  auth  = var.GRAFANA_ADMIN_AUTH
}

# L'org par défaut (id 1, "Main Org.") conserve tous les dashboards et
# datasources existants : on la renomme simplement "Cedille" plutôt que
# de ré-importer les dashboards dans une nouvelle org. Import unique à
# faire avant le premier apply (voir docs/grafana-orgs-2026-11):
#   tofu import grafana_organization.cedille 1
# L'appartenance à l'org est gérée par OIDC (auto_assign_org + groupes
# Authentik), pas par Terraform : ignore_changes empêche un apply de
# retirer les utilisateurs ajoutés lors des logins.
resource "grafana_organization" "cedille" {
  provider = grafana.admin
  name     = "Cedille"

  lifecycle {
    ignore_changes = [admins, editors, viewers, users_without_access]
  }
}

# Nouvelle org isolée. Aucun dashboard/datasource n'y est provisionné
# pour l'instant : les siens seront à créer séparément. Les membres sont
# ajoutés automatiquement par org_mapping (voir helm/values.yaml) lors de
# leur prochain login Authentik, avec le rôle de leur groupe.
resource "grafana_organization" "lan_ets" {
  provider = grafana.admin
  name     = "Lan_ETS"

  lifecycle {
    ignore_changes = [admins, editors, viewers, users_without_access]
  }
}

# Le dossier est créé par le sidecar de dashboards du chart Grafana (voir
# apps/grafana/resources/dashboards/k8s-app-logs-overview.yaml, annotation
# k8s-sidecar-target-directory: "Kubernetes"), pas par Terraform -- on le
# référence ici plutôt que de le créer. `terraform apply` sur ce module doit
# donc arriver APRÈS que ce ConfigMap soit synchronisé par ArgoCD (la
# recherche par titre échoue tant que le dossier n'existe pas encore côté
# Grafana).
data "grafana_folder" "k8s_app_logs" {
  title = "Kubernetes"
}

# role_attribute_path (apps/grafana/helm/values.yaml) accorde déjà le rôle
# intégré "Editor" aux deux seuls groupes Authentik staff (voir
# terraform/grafana/authentik-vault) -- restreindre par rôle intégré plutôt
# que par Team contourne l'absence de Team Sync en Grafana OSS (Enterprise
# uniquement, déjà noté dans ce module authentik-vault).
#
# Remplace l'intégralité des permissions du dossier -- sans Viewer dans la
# liste, les comptes Viewer (tout compte Authentik qui se connecte,
# allow_sign_up: true) ne voient plus ce dossier ni les dashboards qu'il
# contient.
#
# LIMITE CONNUE: ceci ne restreint que la navigation dashboards/dossiers.
# Un Viewer peut toujours interroger le datasource Loki directement via
# Explore -- restreindre l'accès à un datasource par rôle
# (grafana_data_source_permission) est une fonctionnalité Grafana
# ENTERPRISE uniquement (confirmé dans la doc du provider : cette ressource
# est classée "Grafana Enterprise", contrairement à grafana_folder_permission
# qui est "Grafana OSS"). Ce cluster tourne en OSS -- il n'y a donc toujours
# aucun moyen étanche de cacher le datasource Loki lui-même aux Viewers de
# Cedille dans Explore. Deux options si ce point doit être fermé : une
# licence Enterprise, ou déplacer le contenu staff-only dans une org
# séparée. L'org Lan_ETS créée ci-dessus est bien séparée, mais les
# dashboards et datasources n'y ont PAS été déplacés : le risque Explore
# reste donc entier dans Cedille.
resource "grafana_folder_permission" "k8s_app_logs" {
  folder_uid = data.grafana_folder.k8s_app_logs.uid

  # Viewer est indispensable : cette ressource remplace l'intégralité des
  # permissions du dossier. Sans elle, tout compte Authentik Viewer
  # (allow_sign_up: true) ne voit plus le dossier ni ses dashboards.
  permissions {
    role       = "Viewer"
    permission = "View"
  }
  permissions {
    role       = "Editor"
    permission = "View"
  }
  permissions {
    role       = "Admin"
    permission = "Admin"
  }
}
