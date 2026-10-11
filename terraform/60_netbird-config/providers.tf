terraform {
  required_version = ">= 1.11"

  required_providers {
    netbird = {
      source  = "netbirdio/netbird"
      version = "~> 0.0.10"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

locals {
  kubeconfig_path = coalesce(var.kubeconfig_path, "${path.module}/../../.kube/config")
}

provider "kubernetes" {
  config_path = local.kubeconfig_path
}

data "kubernetes_secret_v1" "netbird_pat" {
  metadata {
    name      = "netbird-mgmt-api-key"
    namespace = "netbird-operator"
  }
}

provider "netbird" {
  management_url = var.netbird_url
  token          = data.kubernetes_secret_v1.netbird_pat.data["NB_API_KEY"]
}
