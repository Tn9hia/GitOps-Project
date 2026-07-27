# OpenStack Credentials
variable "ops_username" {
  type        = string
  description = "Tenant usename"
}

variable "ops_password" {
  type        = string
  sensitive   = true
  description = "Tenant password"
}

variable "ops_auth_url" {
  type        = string
  description = "Authentication URL"
}

variable "ops_region" {
  type        = string
  description = "Region name"
}

variable "ops_tenant_name" {
  type        = string
  description = "Tenant name"
}

variable "ops_user_domain_name" {
  type        = string
  description = "User domain name"
}

variable "ops_project_domain_name" {
  type        = string
  description = "Project domain name"
}


# Networking
variable "private_subnet_cidr" {
  type        = string
  description = "CIDR for private subnet"
}

variable "private_subnet_gateway_ip" {
  type        = string
  description = "Gateway IP for private subnet"
}

variable "private_subnet_allocation_pool_start" {
  type        = string
  description = "Start of allocation pool for private subnet"
}

variable "private_subnet_allocation_pool_end" {
  type        = string
  description = "End of allocation pool for private subnet"
}

variable "router_name" {
  type        = string
  description = "Name of the openstack router"
}

# Computing
