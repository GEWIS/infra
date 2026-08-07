terraform {
  required_version = ">= 1.11"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
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
