# OpenStack Credentials
variable "ops_username" {
  type = string
  description = "Tenant usename"
}
variable "ops_password" {
  type = string
  sensitive = true
  description = "Tenant password"
}
variable "ops_auth_url" {
  type = string
  description = "Authentication URL"
}
variable "ops_region" {
  type = string
  description = "Region name"
}
variable "ops_tenant_name" {
  type = string
  description = "Tenant name"
}