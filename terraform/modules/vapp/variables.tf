# Source Template
variable "catalog_org" {
  type    = string
  default = "NghiaLT"
}
variable "catalog_name" {
  type    = string
  default = "NghiaLT-Catalog"
}
variable "template_name" {
  type    = string
  default = "Ubuntu24"
}
variable "storage_profile" {
  type    = string
  default = "*"
}

# Network
variable "networks" {
  type = list(object({
    name               = string
    ip_allocation_mode = optional(string, "MANUAL")
    ip                 = optional(string, null) # Bắt buộc khi ip_allocation_mode = "MANUAL"
    adapter_type       = optional(string, "VMXNET3")
    is_primary         = optional(bool, false)
  }))
  # Thứ tự trong list = thứ tự NIC (index 0 = eth0, index 1 = eth1, ...)
}
# Compute
variable "cpu" {
  type    = number
  default = 2
}
variable "cpu_core" {
  type    = number
  default = 1
}
variable "ram" {
  type    = number
  default = 4096
}

# Storage
variable "os_disk_size" {
  type    = number
  default = 20480
}

variable "data_disks" {
  type = list(object({
    size_in_mb      = number
    storage_profile = optional(string, "Bronze Storage Policy")
  }))
  default = []
}


# VM customization
variable "vm_name" {
  type = string
}
variable "vm_password" {
  type      = string
  sensitive = true
}
