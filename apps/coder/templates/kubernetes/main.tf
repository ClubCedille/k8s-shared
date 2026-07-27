# Template Coder "kubernetes" -- provisionne un workspace de dev sous forme de
# pod dans le namespace `coder-workspaces` du cluster k8s-shared.
#
# Poussé dans Coder avec :
#   coder templates push kubernetes -d apps/coder/templates/kubernetes
#
# Tourne à l'intérieur du pod coderd : la config kubernetes provider utilise
# donc le ServiceAccount in-cluster (voir la Role/RoleBinding créées par
# coder.serviceAccount.workspaceNamespaces dans apps/coder/helm/values.yaml).

terraform {
  required_version = ">=1.14"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
}

locals {
  namespace = "coder-workspaces"
}

provider "kubernetes" {
  config_path = null # in-cluster config
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "Nombre de coeurs CPU."
  type         = "number"
  default      = "2"
  mutable      = true
  option {
    name  = "2 vCPU"
    value = "2"
  }
  option {
    name  = "4 vCPU"
    value = "4"
  }
  option {
    name  = "8 vCPU"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Mémoire (Gi)"
  type         = "number"
  default      = "4"
  mutable      = true
  option {
    name  = "4 Gi"
    value = "4"
  }
  option {
    name  = "8 Gi"
    value = "8"
  }
  option {
    name  = "16 Gi"
    value = "16"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Taille du disque (Gi)"
  description  = "Persiste entre les redémarrages du workspace (ceph-rbd)."
  type         = "number"
  default      = "10"
  mutable      = false
}

data "coder_parameter" "image" {
  name         = "image"
  display_name = "Image de base"
  type         = "string"
  default      = "docker.io/codercom/enterprise-base:ubuntu"
  mutable      = true
  option {
    name  = "Ubuntu (base)"
    value = "docker.io/codercom/enterprise-base:ubuntu"
  }
  option {
    name  = "Node.js"
    value = "docker.io/codercom/enterprise-node:ubuntu"
  }
}

resource "coder_agent" "main" {
  os             = "linux"
  arch           = "amd64"
  startup_script = <<-EOT
    set -e
    if [ ! -f "$${HOME}/.init_done" ]; then
      touch "$${HOME}/.init_done"
    fi

    # code-server pour l'accès web (voir coder_app ci-dessous)
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
  EOT
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/?folder=/home/coder"
  icon         = "/icon/code.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = local.namespace
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "ceph-rbd"
    resources {
      requests = {
        storage = "${data.coder_parameter.home_disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/part-of" = "coder-workspaces"
      "coder.owner"               = data.coder_workspace_owner.me.name
      "coder.workspace"           = data.coder_workspace.me.name
    }
  }
  spec {
    security_context {
      run_as_user = 1000
      fs_group    = 1000
    }

    container {
      name    = "dev"
      image   = data.coder_parameter.image.value
      command = ["sh", "-c", coder_agent.main.init_script]

      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }

      resources {
        requests = {
          cpu    = data.coder_parameter.cpu.value
          memory = "${data.coder_parameter.memory.value}Gi"
        }
        limits = {
          cpu    = data.coder_parameter.cpu.value
          memory = "${data.coder_parameter.memory.value}Gi"
        }
      }

      volume_mount {
        mount_path = "/home/coder"
        name       = "home"
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.home.metadata[0].name
      }
    }
  }
}
