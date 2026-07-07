# Define data source
data "vcd_org_vdc" "default-vdc" {
  org  = var.vcd_org
  name = var.vcd_vdc
}

data "vcd_nsxt_edgegateway" "default-edgegateway" {
  org  = var.vcd_org
  name = var.vcd_edgegateway
}

# Define resource
# Isolate the network for the VMs
resource "vcd_network_isolated_v2" "Isolated-Network" {
  org      = var.vcd_org
  owner_id = data.vcd_org_vdc.default-vdc.id

  name        = "Isolated-Network"
  description = "Isolated VDC network backed by NSX-T"

  gateway       = "172.16.10.254"
  prefix_length = 24

  guest_vlan_allowed = false

  static_ip_pool {
    start_address = "172.16.10.1"
    end_address   = "172.16.10.100"
  }
}

# Routed network for the VMs
resource "vcd_network_routed_v2" "Routed-Network" {
  org = var.vcd_org
  # owner_id    = data.vcd_org_vdc.default-vdc.id
  name        = "Routed-Network"
  description = "Routed Org VDC network backed by NSX-T"

  edge_gateway_id = data.vcd_nsxt_edgegateway.default-edgegateway.id

  gateway            = "192.168.100.254"
  prefix_length      = 24
  guest_vlan_allowed = false

  static_ip_pool {
    start_address = "192.168.100.1"
    end_address   = "192.168.100.100"
  }
}

# Create Squid VM from vapp module
module "squid" {
  source = "./modules/vapp"

  vm_name     = "squid"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 2
  cpu_core        = 1
  ram             = 2048
  os_disk_size    = 20480
  storage_profile = "Bronze Storage Policy"

  networks = [
    {
      name               = vcd_network_routed_v2.Routed-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "192.168.100.1"
      is_primary         = true
    },
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.1"
      is_primary         = false
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# Create PowerDNS VM from vapp module
module "dns" {
  source = "./modules/vapp"

  vm_name     = "powerdns"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 2
  cpu_core        = 1
  ram             = 2048
  os_disk_size    = 20480
  storage_profile = "Bronze Storage Policy"

  networks = [
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.2"
      is_primary         = true
    },
    {
      name               = vcd_network_routed_v2.Routed-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "192.168.100.2"
      is_primary         = false
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# Create NTPSec VM from vapp module
module "ntpsec" {
  source = "./modules/vapp"

  vm_name     = "ntpsec"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 2
  cpu_core        = 1
  ram             = 2048
  os_disk_size    = 20480
  storage_profile = "Bronze Storage Policy"

  networks = [
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.3"
      is_primary         = false
    },
    {
      name               = vcd_network_routed_v2.Routed-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "192.168.100.3"
      is_primary         = true
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# Create apt package mirror VM from vapp module
module "apt_mirror" {
  source = "./modules/vapp"

  vm_name     = "apt-mirror"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 2
  cpu_core        = 1
  ram             = 2048
  os_disk_size    = 20480
  storage_profile = "Bronze Storage Policy"

  data_disks = [
    { size_in_mb = 307200 }, # 300 GB data disk
  ]

  networks = [
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.4"
      is_primary         = false
    },
    {
      name               = vcd_network_routed_v2.Routed-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "192.168.100.4"
      is_primary         = true
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# Create Hanshicorp Vault VM from vapp module
module "vault" {
  source = "./modules/vapp"

  vm_name     = "vault"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 2
  cpu_core        = 1
  ram             = 2048
  os_disk_size    = 20480
  storage_profile = "Bronze Storage Policy"

  networks = [
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.5"
      is_primary         = true
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# Create Jump VM from vapp module
module "client" {
  source = "./modules/vapp"

  vm_name     = "client"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 2
  cpu_core        = 1
  ram             = 2048
  os_disk_size    = 20480
  storage_profile = "Bronze Storage Policy"

  networks = [
    {
      name               = vcd_network_routed_v2.Routed-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "192.168.100.100"
      is_primary         = true
    },
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.100"
      is_primary         = false
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# HAProxy for load balancing
module "haproxy" {
  source   = "./modules/vapp"
  vm_name     = "haproxy"
  vm_password = var.vm_password
  catalog_name  = var.catalog_name
  template_name = var.template_name
  cpu             = 2
  cpu_core        = 1
  ram             = 4096
  os_disk_size    = 30720
  storage_profile = "Bronze Storage Policy"
  networks = [
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.6"
      is_primary         = false
    },
    {
      name               = vcd_network_routed_v2.Routed-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "192.168.100.6"
      is_primary         = true
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# Gitlab for DevOps platform
module "gitlab" {

  source = "./modules/vapp"

  vm_name     = "gitlab"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 4
  cpu_core        = 1
  ram             = 8192
  os_disk_size    = 51200
  storage_profile = "Bronze Storage Policy"

  networks = [
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.7"
      is_primary         = true
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# # Gitlab Runner for CI/CD pipeline
module "runner" {
  source = "./modules/vapp"

  vm_name     = "runner"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 4
  cpu_core        = 1
  ram             = 2048
  os_disk_size    = 20480
  storage_profile = "Bronze Storage Policy"

  networks = [
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.8"
      is_primary         = true
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# Harbor for container registry
module "harbor" {
  source = "./modules/vapp"

  vm_name     = "harbor"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 4
  cpu_core        = 1
  ram             = 4096
  os_disk_size    = 20480
  storage_profile = "Bronze Storage Policy"

  data_disks = [
    { size_in_mb = 51200 }, # 50 GB data disk
  ]

  networks = [
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.9"
      is_primary         = true
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# Atlantis to running terraform commands from pull request
module "atlantis" {
  source = "./modules/vapp"

  vm_name     = "atlantis"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 4
  cpu_core        = 1
  ram             = 2048
  os_disk_size    = 20480
  storage_profile = "Bronze Storage Policy"

  networks = [
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.10"
      is_primary         = true
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}

# Atlantis to running terraform commands from pull request
module "test" {
  source = "./modules/vapp"

  vm_name     = "test"
  vm_password = var.vm_password

  catalog_name  = var.catalog_name
  template_name = var.template_name

  cpu             = 4
  cpu_core        = 1
  ram             = 2048
  os_disk_size    = 20480
  storage_profile = "Bronze Storage Policy"

  networks = [
    {
      name               = vcd_network_isolated_v2.Isolated-Network.name
      ip_allocation_mode = "MANUAL"
      ip                 = "172.16.10.20"
      is_primary         = true
    },
  ]

  depends_on = [
    vcd_network_routed_v2.Routed-Network,
    vcd_network_isolated_v2.Isolated-Network,
  ]
}



# === TEST RESOURCES ===
# # Create three VM for k8s control plane nodes from vapp module
# variable "k8s-controlplane" {
#   type = map(object({
#     ip = string
#   }))
#   default = {
#     "control-plane-01" = { ip = "172.16.10.20" }
#   }
# }

# module "k8s_control_plane" {
#   source   = "./modules/vapp"
#   for_each = var.k8s-controlplane

#   vm_name     = each.key
#   vm_password = var.vm_password

#   catalog_name  = var.catalog_name
#   template_name = var.template_name

#   cpu             = 4
#   cpu_core        = 1
#   ram             = 4096
#   os_disk_size    = 51200
#   storage_profile = "Bronze Storage Policy"

#   networks = [
#     {
#       name               = vcd_network_isolated_v2.Isolated-Network.name
#       ip_allocation_mode = "MANUAL"
#       ip                 = each.value.ip
#       is_primary         = true
#     },
#   ]

#   depends_on = [
#     vcd_network_routed_v2.Routed-Network,
#     vcd_network_isolated_v2.Isolated-Network,
#   ]
# }

# # Create three VM for k8s worker nodes from vapp module
# variable "k8s-worker" {
#   type = map(object({
#     ip = string
#   }))
#   default = {
#     "worker-01" = { ip = "172.16.10.30" }
#     "worker-02" = { ip = "172.16.10.31" }
#     "worker-03" = { ip = "172.16.10.32" }
#   }
# }

# module "k8s_worker" {
#   source   = "./modules/vapp"
#   for_each = var.k8s-worker

#   vm_name     = each.key
#   vm_password = var.vm_password

#   catalog_name  = var.catalog_name
#   template_name = var.template_name

#   cpu             = 4
#   cpu_core        = 1
#   ram             = 4096
#   os_disk_size    = 30720
#   storage_profile = "Bronze Storage Policy"

#   data_disks = [
#     { size_in_mb = 51200 }, # 50 GB data disk
#   ]

#   networks = [
#     {
#       name               = vcd_network_isolated_v2.Isolated-Network.name
#       ip_allocation_mode = "MANUAL"
#       ip                 = each.value.ip
#       is_primary         = true
#     },
#   ]

#   depends_on = [
#     vcd_network_routed_v2.Routed-Network,
#     vcd_network_isolated_v2.Isolated-Network,
#   ]
# }
