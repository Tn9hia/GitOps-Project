# Define required providers
terraform {
required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
  }
}

# Configure the OpenStack Provider
provider "openstack" {
  user_name   = var.ops_username
  tenant_name = var.ops_tenant_name
  password    = var.ops_password
  auth_url    = var.ops_auth_url
  region      = var.ops_region
}