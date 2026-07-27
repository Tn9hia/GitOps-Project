# Data sources
data "openstack_images_image_v2" "this" {
  name = var.vm_image_name
}

data "openstack_compute_flavor_v2" "this" {
  name = var.vm_flavor_name
}

data "openstack_compute_keypair_v2" "this" {
  name = var.vm_key_pair
}

# Configure the VM instance
resource "openstack_compute_instance_v2" "this" {
  # Define the compute
  name = var.vm_name
  # Do not set image_id when booting from a block device
  image_id          = length(var.vm_block_devices) > 0 ? null : data.openstack_images_image_v2.this.id
  flavor_id         = data.openstack_compute_flavor_v2.this.id
  key_pair          = var.vm_key_pair
  availability_zone = var.vm_availability_zone
  security_groups   = var.vm_security_groups
  metadata          = var.vm_metadata

  # Define block devices
  dynamic "block_device" {
    for_each = var.vm_block_devices
    content {
      # An image-backed device falls back to the image looked up above
      uuid                  = block_device.value.source_type == "image" ? coalesce(block_device.value.uuid, data.openstack_images_image_v2.this.id) : block_device.value.uuid
      source_type           = block_device.value.source_type
      destination_type      = block_device.value.destination_type
      volume_size           = block_device.value.volume_size
      boot_index            = block_device.value.boot_index
      volume_type           = block_device.value.volume_type
      delete_on_termination = block_device.value.delete_on_termination
    }
  }

  # Define network interfaces (static/manual fixed_ip_v4, no DHCP)
  dynamic "network" {
    for_each = var.vm_networks
    content {
      uuid        = network.value.uuid
      fixed_ip_v4 = network.value.fixed_ip_v4
    }
  }
}