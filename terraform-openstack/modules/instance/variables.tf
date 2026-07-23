# Compute variable
variable "vm_name" {
  type = string
  description = "Display name of the virtual machine"
}

variable "vm_availability_zone" {
  type = string
  default = "AZ-01"
  description = "Availability zone for the VM"
}

variable "vm_image_name" {
  type = string
  default = "Ubuntu-24.04-CIS"
  description = "Name of the image to use for the VM"
}

variable "vm_flavor_name" {
  type = string
  default = "c1.medium"
  description = "Name of the flavor to use for the VM"
}

variable "vm_key_pair" {
  type = string
  default = "balck"
  description = "Name of the key pair to associate with the VM"
}

variable "vm_security_groups" {
  type = list(string)
  default = ["pfSense-curt"]
  description = "List of security group names to assign to the VM"
}

# Block Storage variables
variable "vm_block_devices" {
  description = "Map of block devices"
  type = map(object({
    uuid                   = optional(string)           # required if source_type is image or volume
    source_type            = string                     # "image" | "volume" | "blank" | "snapshot"
    destination_type       = optional(string, "volume")
    volume_size             = number
    boot_index              = number                    # 0 = boot device, -1 = data device
    delete_on_termination   = optional(bool, false)     # Whether to delete the volume when the instance is deleted
  }))

  validation {
    condition = alltrue([
      for k, v in var.vm_block_devices :
      v.source_type != "image" || v.uuid != null
    ])
    error_message = "block_device with source_type = 'image' must have uuid."
  }

  validation {
    condition     = length([for k, v in var.vm_block_devices : v if v.boot_index == 0]) <= 1
    error_message = "Only one block_device may have boot_index = 0 (boot volume)."
  }
}

# Network variables
variable "vm_networks" {
  type = list(object({
    uuid        = string # network ID to attach
    fixed_ip_v4 = string # static (manual) IPv4 address on this network, no DHCP
  }))
  description = "List of networks to attach to the VM. Each entry creates one network interface with a manually assigned fixed_ip_v4 (default VM interface = 1 entry in this list)."
}

# Floating IP variables (optional - only created when vm_floating_ip_pool is set)
variable "vm_floating_ip_pool" {
  type        = string
  default     = null
  description = "Name of the external network (floating IP pool) to allocate a floating IP from. When set, a floating IP is created and associated with the VM. Leave unset to skip floating IP entirely."
}

variable "vm_floating_ip_fixed_ip" {
  type        = string
  default     = null
  description = "fixed_ip_v4 (from vm_networks) that the floating IP should bind to. Defaults to the fixed_ip_v4 of the first network in vm_networks when not set."
}