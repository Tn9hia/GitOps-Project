# Data sources
data "openstack_compute_image_v2" "this" {
  name = var.vm_image_name
}

data "openstack_compute_flavor_v2" "this" {
  name = var.vm_flavor_name
}

data "openstack_compute_keypair_v2" "this" {
  name = var.vm_key_pair
}

# Resource
resource "openstack_compute_instance_v2" "this" {
  # Define the VM instance
  name            = var.vm_name
  image_id        = data.openstack_compute_image_v2.this.id
  flavor_id       = data.openstack_compute_flavor_v2.this.id
  key_pair        = var.vm_key_pair
  availability_zone = var.vm_availability_zone
  security_groups = var.vm_security_groups
  metadata = var.vm_metadata

  # Define block devices
  dynamic "block_device" {
    for_each = var.vm_block_devices
    content {
      uuid                  = block_device.value.uuid
      source_type           = block_device.value.source_type
      destination_type     = block_device.value.destination_type
      volume_size           = block_device.value.volume_size
      boot_index            = block_device.value.boot_index
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

# Floating IP - only provisioned when vm_floating_ip_pool is declared
resource "openstack_networking_floatingip_v2" "this" {
  count = var.vm_floating_ip_pool != null ? 1 : 0

  pool = var.vm_floating_ip_pool
}

resource "openstack_networking_floatingip_associate_v2" "this" {
  count = var.vm_floating_ip_pool != null ? 1 : 0

  floating_ip = openstack_networking_floatingip_v2.this[0].address
  port_id     = openstack_compute_instance_v2.this.network[0].port
  fixed_ip    = coalesce(var.vm_floating_ip_fixed_ip, var.vm_networks[0].fixed_ip_v4)
}