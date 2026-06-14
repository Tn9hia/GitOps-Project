# VApp resource
resource "vcd_vapp" "this" {
  name = var.vm_name
}

# Source vAPP template
data "vcd_catalog" "this" {
  org  = var.catalog_org
  name = var.catalog_name
}
data "vcd_catalog_vapp_template" "this" {
  org        = var.catalog_org
  catalog_id = data.vcd_catalog.this.id
  name       = var.template_name
}

# Attach org networks to vApp so VMs inside can see them
resource "vcd_vapp_org_network" "this" {
  for_each         = { for net in var.networks : net.name => net }
  vapp_name        = vcd_vapp.this.name
  org_network_name = each.value.name
  reboot_vapp_on_removal = true
}

# VApp's VM resource
resource "vcd_vapp_vm" "this" {
  depends_on = [vcd_vapp_org_network.this]
  vapp_name        = vcd_vapp.this.name
  name             = var.vm_name
  computer_name    = var.vm_name
  vapp_template_id = data.vcd_catalog_vapp_template.this.id
  memory           = var.ram
  cpus             = var.cpu
  cpu_cores        = var.cpu_core

  dynamic "network" {
    for_each = var.networks
    content {
      type               = "org"
      name               = network.value.name
      adapter_type       = network.value.adapter_type
      ip_allocation_mode = network.value.ip_allocation_mode
      ip                 = network.value.ip
      is_primary         = network.value.is_primary
    }
  }
  override_template_disk {
    bus_type        = "paravirtual"
    size_in_mb      = var.os_disk_size
    bus_number      = 0
    unit_number     = 0
    iops            = 0
    storage_profile = var.storage_profile
  }
  customization {
    enabled                    = true
    allow_local_admin_password = true
    auto_generate_password     = false
    admin_password             = var.vm_password
  }
}

# Additional data disks (unit_number bắt đầu từ 1 vì 0 là OS disk)
resource "vcd_vm_internal_disk" "data" {
  for_each = { for i, d in var.data_disks : tostring(i) => d }

  vapp_name       = vcd_vapp.this.name
  vm_name         = vcd_vapp_vm.this.name
  bus_type        = "paravirtual"
  size_in_mb      = each.value.size_in_mb
  bus_number      = 0
  unit_number     = tonumber(each.key) + 1
  storage_profile = each.value.storage_profile

  depends_on = [vcd_vapp_vm.this]
}
