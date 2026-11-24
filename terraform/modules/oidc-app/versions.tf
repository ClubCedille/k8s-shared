terraform {
  required_version = ">=1.14"

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = ">= 2026.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.8.1"
    }
  }
}
