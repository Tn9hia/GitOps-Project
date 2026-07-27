# Compute variable
variable "vm_name" {
  type        = string
  description = "Display name of the virtual machine"
}

variable "vm_availability_zone" {
  type        = string
  description = "Availability zone for the VM"
}

variable "vm_image_name" {
  type        = string
  description = "Name of the image to use for the VM"
}

variable "vm_flavor_name" {
  type        = string
  description = "Name of the flavor to use for the VM"
}

variable "vm_key_pair" {
  type        = string
  description = "Name of the key pair to associate with the VM"
}

variable "vm_security_groups" {
  type        = list(string)
  description = "List of security group names to assign to the VM"
}

variable "vm_metadata" {
  type        = map(string)
  description = "Map of metadata to associate with the VM"
}

# Block Storage variables
variable "vm_block_devices" {
  description = "List of block devices, in attachment order"
  type = list(object({
    uuid                  = optional(string) # defaults to vm_image_name when source_type is image
    source_type           = string           # "image" | "volume" | "blank" | "snapshot"
    destination_type      = optional(string, "volume")
    volume_size           = number
    boot_index            = number                # 0 = boot device, -1 = data device
    volume_type           = string
    delete_on_termination = optional(bool, false) # Whether to delete the volume when the instance is deleted
  }))

  validation {
    condition     = length([for v in var.vm_block_devices : v if v.boot_index == 0]) <= 1
    error_message = "Only one block_device may have boot_index = 0 (boot volume)."
  }
}

# Network variables
variable "vm_networks" {
  type = list(object({
    uuid        = string
    fixed_ip_v4 = string
  }))
  description = "List of network UUIDs and fixed IPs to attach to the VM"
}