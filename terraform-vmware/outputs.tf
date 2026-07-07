# Networks
output "isolated_network" {
  value = {
    name    = vcd_network_isolated_v2.Isolated-Network.name
    gateway = vcd_network_isolated_v2.Isolated-Network.gateway
    prefix  = vcd_network_isolated_v2.Isolated-Network.prefix_length
  }
}

output "routed_network" {
  value = {
    name    = vcd_network_routed_v2.Routed-Network.name
    gateway = vcd_network_routed_v2.Routed-Network.gateway
    prefix  = vcd_network_routed_v2.Routed-Network.prefix_length
  }
}

# Infrastructure VMs
output "squid" {
  value = {
    name = module.squid.vm_name
    ips  = module.squid.vm_ips
  }
}

output "dns" {
  value = {
    name = module.dns.vm_name
    ips  = module.dns.vm_ips
  }
}

output "ntpsec" {
  value = {
    name = module.ntpsec.vm_name
    ips  = module.ntpsec.vm_ips
  }
}

output "apt_mirror" {
  value = {
    name       = module.apt_mirror.vm_name
    ips        = module.apt_mirror.vm_ips
    data_disks = module.apt_mirror.data_disk_ids
  }
}

output "vault" {
  value = {
    name = module.vault.vm_name
    ips  = module.vault.vm_ips
  }
}

output "client" {
  value = {
    name = module.client.vm_name
    ips  = module.client.vm_ips
  }
}

output "haproxy" {
  value = {
    name = module.haproxy.vm_name
    ips  = module.haproxy.vm_ips
  }
}

output "gitlab" {
  value = {
    name = module.gitlab.vm_name
    ips  = module.gitlab.vm_ips
  }
}

output "runner" {
  value = {
    name = module.runner.vm_name
    ips  = module.runner.vm_ips
  }
}

output "harbor" {
  value = {
    name = module.harbor.vm_name
    ips  = module.harbor.vm_ips
  }
}

output "atlantis" {
  value = {
    name = module.atlantis.vm_name
    ips  = module.atlantis.vm_ips
  }
}

# Kubernetes nodes
# output "k8s_control_plane" {
#   value = {
#     for name, mod in module.k8s_control_plane : name => {
#       ips = mod.vm_ips
#     }
#   }
# }

# output "k8s_workers" {
#   value = {
#     for name, mod in module.k8s_worker : name => {
#       ips        = mod.vm_ips
#       data_disks = mod.data_disk_ids
#     }
#   }
# }
