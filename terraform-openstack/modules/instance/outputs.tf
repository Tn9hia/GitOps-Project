output "id" {
  description = "ID of the VM instance"
  value       = openstack_compute_instance_v2.this.id
}

output "name" {
  description = "Name of the VM instance"
  value       = openstack_compute_instance_v2.this.name
}

output "access_ip_v4" {
  description = "IPv4 address assigned to the VM instance"
  value       = openstack_compute_instance_v2.this.access_ip_v4
}
