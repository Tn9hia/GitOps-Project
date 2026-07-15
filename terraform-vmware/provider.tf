terraform {
  required_providers {
    vcd = {
      source  = "vmware/vcd"
      version = "3.14.1"
    }
  }

  backend "http" {
    address        = "https://gitlab.nghia.internal/api/v4/projects/5/terraform/state/default"
    lock_address   = "https://gitlab.nghia.internal/api/v4/projects/5/terraform/state/default/lock"
    unlock_address = "https://gitlab.nghia.internal/api/v4/projects/5/terraform/state/default/lock"
    lock_method    = "POST"
    unlock_method  = "DELETE"
    username       = "nghia"
    password       = var.gitlab_token
  }
}

provider "vcd" {
  user                 = var.vcd_user
  password             = var.vcd_pass
  auth_type            = "integrated"
  org                  = var.vcd_org
  vdc                  = var.vcd_vdc
  url                  = var.vcd_url
  max_retry_timeout    = var.vcd_max_retry_timeout
  allow_unverified_ssl = var.vcd_allow_unverified_ssl
}
