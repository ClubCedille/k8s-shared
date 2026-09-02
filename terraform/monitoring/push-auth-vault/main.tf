terraform {
  required_version = ">=1.14"
  backend "kubernetes" {
    secret_suffix = "state-monitoring-push-auth"
    namespace     = "terraform"
    config_path   = "~/.kube/config"
  }

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.8.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.9.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.2"
    }
  }
}

provider "vault" {
  address          = "https://vault.etsmtl.club"
  skip_child_token = true
}

locals {
  # One basic-auth credential per remote_write/loki.write source (mimir,
  # loki) consumed by monitoring01's Prometheus and Alloy -- see the
  # Grafana/Mimir/Loki plan (Plateforme-Cedille#654 phase 2).
  apps = {
    mimir = "prometheus"
    loki  = "alloy"
  }
}

resource "random_password" "push_password" {
  for_each = local.apps

  length           = 32
  special          = true
  override_special = "!-_="
}

# The mimir-distributed and loki charts' nginx gateway (gateway.nginx.
# basicAuth / gateway.basicAuth) expect an existing Secret with a literal
# '.htpasswd' key -- computed here with openssl (apr1/MD5-crypt, universally
# available, unlike the `htpasswd` binary) rather than in-cluster, since
# neither chart's own htpasswd-from-plaintext option can source the
# password from Vault without checking it into values.yaml in the clear.
resource "terraform_data" "htpasswd" {
  for_each = local.apps

  input = {
    username = each.value
    password = random_password.push_password[each.key].result
  }

  provisioner "local-exec" {
    command = "printf '%s:%s\\n' \"${each.value}\" \"$(openssl passwd -apr1 '${random_password.push_password[each.key].result}')\" > \"${path.module}/.htpasswd-${each.key}\""
  }
}

data "local_file" "htpasswd" {
  for_each   = local.apps
  filename   = "${path.module}/.htpasswd-${each.key}"
  depends_on = [terraform_data.htpasswd]
}

resource "vault_kv_secret" "push_htpasswd" {
  for_each = local.apps

  path = "kv/data/monitoring/${each.key}-push-htpasswd"

  data_json = jsonencode({
    username    = each.value
    password    = random_password.push_password[each.key].result
    ".htpasswd" = chomp(data.local_file.htpasswd[each.key].content)
  })
}
