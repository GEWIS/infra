terraform {
  required_version = ">= 1.11"

  required_providers {
    garage = {
      source  = "vhco-pro/garage"
      version = "0.1.4"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
  }
}

provider "garage" {
  endpoint = var.garage_endpoint
  token    = var.garage_admin_token
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
