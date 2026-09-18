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

# Le dossier est créé par le sidecar de dashboards du chart Grafana (voir
# apps/grafana/resources/dashboards/k8s-app-logs-overview.yaml, annotation
# k8s-sidecar-target-directory: "Kubernetes/App-Logs"), pas par Terraform --
# on le référence ici plutôt que de le créer. `terraform apply` sur ce
# module doit donc arriver APRÈS que ce ConfigMap soit synchronisé par
# ArgoCD (la recherche par titre échoue tant que le dossier n'existe pas
# encore côté Grafana).
data "grafana_folder" "k8s_app_logs" {
  title = "App-Logs"
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
# qui est "Grafana OSS"). Ce cluster tourne en OSS -- il n'y a donc
# actuellement aucun moyen étanche de cacher le datasource Loki lui-même aux
# Viewers dans Explore. Deux options si ce point doit être fermé : une
# licence Enterprise, ou déplacer le contenu staff-only dans un Org Grafana
# séparé (les Viewers n'y étant jamais invités, le datasource n'existe
# simplement pas pour eux). Aucune des deux n'est faite ici.
resource "grafana_folder_permission" "k8s_app_logs" {
  folder_uid = data.grafana_folder.k8s_app_logs.uid

  permissions {
    role       = "Editor"
    permission = "View"
  }
  permissions {
    role       = "Admin"
    permission = "Admin"
  }
}
