terraform {
  required_version = ">= 1.11"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
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

data "kubernetes_secret_v1" "provisioner" {
  metadata {
    name      = "postgres-app"
    namespace = "postgres"
  }
}

provider "vault" {
  address = var.bao_address

  auth_login {
    path = "auth/kubernetes/login"
    parameters = {
      role = var.bao_role
      jwt  = var.bao_jwt
    }
  }
}

provider "postgresql" {
  host            = var.postgres_host
  port            = var.postgres_port
  username        = data.kubernetes_secret_v1.provisioner.data["username"]
  password        = data.kubernetes_secret_v1.provisioner.data["password"]
  sslmode         = "require"
  superuser       = false
  connect_timeout = 15
}
