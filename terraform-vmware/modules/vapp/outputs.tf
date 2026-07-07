output "vm_id"       { value = vcd_vapp_vm.this.id }
output "vm_name"     { value = vcd_vapp_vm.this.name }
output "vm_ips"      { value = [for nic in vcd_vapp_vm.this.network : nic.ip] }
output "data_disk_ids" {
  value = { for k, d in vcd_vm_internal_disk.data : "disk-${tonumber(k) + 1}" => d.id }
}