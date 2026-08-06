terraform {
  required_version = ">= 1.11"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

locals {
  kubeconfig_path = coalesce(var.kubeconfig_path, "${path.module}/../../.kube/config")
}

provider "helm" {
  kubernetes {
    config_path = local.kubeconfig_path
  }
}

provider "kubectl" {
  config_path      = local.kubeconfig_path
  load_config_file = true
}
