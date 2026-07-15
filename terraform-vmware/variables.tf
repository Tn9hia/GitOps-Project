## Necessary information for login to Viettel Cloud
variable "vcd_user" {
  description = "Username of Viettel Cloud"
  sensitive   = false
}

variable "vcd_pass" {
  description = "Password of Viettel Cloud"
  sensitive   = true
}

variable "vcd_org" {
  description = "Organization of Viettel Cloud"
  sensitive   = false
}

variable "vcd_vdc" {
  description = "Virtual Data Center of Viettel Cloud"
  sensitive   = false
}

variable "vcd_edgegateway" {
  description = "Edge Gateway of Viettel Cloud"
  sensitive   = false
}

variable "vcd_url" {
  description = "URL of Viettel Cloud"
  sensitive   = false
}

variable "vcd_max_retry_timeout" {
  description = "Maximum retry timeout for Viettel Cloud API calls"
  default     = 60
  sensitive   = false
}

variable "vcd_allow_unverified_ssl" {
  description = "Allow unverified SSL certificates for Viettel Cloud API calls"
  default     = false
  sensitive   = false
}

## Catalog
variable "catalog_name" {
  description = "Name of the catalog"
  type        = string
  sensitive   = false
}

variable "template_name" {
  description = "Name of the template"
  type        = string
  default = "Ubuntu24"
  sensitive   = false
}

variable "storage_policy" {
  description = "Storage policy for the VMs"
  type        = string
  default     = "Bronze Storage Policy"
}

## Default VM sizing
variable "vm_cpu" {
  description = "Number of CPUs for the VMs"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Memory for the VMs"
  type        = number
  default     = 2048
}

# VM password
variable "vm_password" {
  description = "Password for the VMs"
  sensitive   = true
  default = "Okela123!@#"
}

variable "gitlab_token" {
  description = "Token for GitLab API authentication"
  sensitive   = true
}
