terraform {
  required_version = ">= 1.11"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.44"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

locals {
  kubeconfig_path = coalesce(var.kubeconfig_path, "${path.module}/../../.kube/config")
}

provider "kubernetes" {
  config_path = local.kubeconfig_path
}

data "kubernetes_secret_v1" "grafana_auth" {
  metadata {
    name      = "grafana-auth"
    namespace = "observability"
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = "${data.kubernetes_secret_v1.grafana_auth.data["admin-user"]}:${data.kubernetes_secret_v1.grafana_auth.data["admin-password"]}"
}
