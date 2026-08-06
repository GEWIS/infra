terraform {
  required_version = ">= 1.11"

  required_providers {
    xenorchestra = {
      source  = "terra-farm/xenorchestra"
      version = "~> 0.31"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}

provider "xenorchestra" {
  url = "wss://xoa.gewis.nl"
}

provider "talos" {}
