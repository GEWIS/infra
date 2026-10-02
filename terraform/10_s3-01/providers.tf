terraform {
  required_version = ">= 1.6"

  required_providers {
    xenorchestra = {
      source  = "terra-farm/xenorchestra"
      version = "~> 0.31"
    }
  }
}

provider "xenorchestra" {
  url = "wss://xoa.gewis.nl"
}
