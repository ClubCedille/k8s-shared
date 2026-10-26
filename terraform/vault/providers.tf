terraform {
  required_version = ">=1.14"
  backend "kubernetes" {
    secret_suffix = "state-vault"
    namespace     = "terraform"
    config_path   = "~/.kube/config"
  }

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.9.0"
    }
  }
}

provider "vault" {
    address          = "https://vault.etsmtl.club"
    skip_child_token = true
}