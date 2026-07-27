# Create private network and connect it to the provider router
data "openstack_networking_router_v2" "router" {
  name = var.router_name
}

resource "openstack_networking_network_v2" "private_network" {
  name           = "balck-vpc"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "private_subnet" {
  name        = "balck-subnet"
  network_id  = openstack_networking_network_v2.private_network.id
  cidr        = var.private_subnet_cidr
  gateway_ip  = var.private_subnet_gateway_ip
  ip_version  = 4

  allocation_pool {
    start = var.private_subnet_allocation_pool_start
    end   = var.private_subnet_allocation_pool_end
  }
}

resource "openstack_networking_router_interface_v2" "router_interface_1" {
  router_id = data.openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.private_subnet.id
}

# Create security group that allows all traffic
resource "openstack_networking_secgroup_v2" "default-sg" {
  name        = "balck-sg"
  description = "Default security group allowing all traffic"
}

resource "openstack_networking_secgroup_rule_v2" "secgroup_rule_1" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 1
  port_range_max    = 65535
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.default-sg.id
}

# Create instances/compute resources and attach them to the private network
# VM Services that run aptly (TCP 80/443), ntpsec(UDP 123) and powerdns (TCP 53)
# Need at least 300 GB of storage for aptly
module "vm_services" {
  source               = "./modules/instance"
  vm_name              = "balck-01"
  vm_availability_zone = "AZ-01"
    vm_image_name        = "Ubuntu-24.04-CIS"
  vm_flavor_name       = "c1.medium"
  vm_key_pair          = "balck"
  vm_security_groups   = [openstack_networking_secgroup_v2.default-sg.name]
  vm_metadata          = {}

  vm_block_devices = [
    {
      source_type           = "image"
      destination_type      = "volume"
      volume_size           = 20
      boot_index            = 0
      volume_type           = "STANDARD"
      delete_on_termination = true
    },
    {
      source_type           = "blank"
      destination_type      = "volume"
      volume_size           = 300
      boot_index            = -1
      volume_type           = "STANDARD"
      delete_on_termination = true
    },    
  ]

  vm_networks = [
    {
      uuid        = openstack_networking_network_v2.private_network.id
      fixed_ip_v4 = "172.16.5.10"
    },
  ]
}

data "openstack_networking_port_v2" "port_of_vm_services" {
  device_id = module.vm_services.id
}

# Floating IP to allow external access to the Services VM
resource "openstack_networking_floatingip_associate_v2" "fip_assoc" {
  floating_ip = "10.128.57.144"          # FIP có sẵn
  port_id     = data.openstack_networking_port_v2.port_of_vm_services.id
}

# Create Gitlab instance
module "gitlab" {
  source               = "./modules/instance"
  vm_name              = "balck-02"
  vm_availability_zone = "AZ-01"
  vm_image_name        = "Ubuntu-24.04-CIS"
  vm_flavor_name       = "c1.large"
  vm_key_pair          = "balck"
  vm_security_groups   = [openstack_networking_secgroup_v2.default-sg.name]
  vm_metadata          = {}

  vm_block_devices = [
    {
      source_type           = "image"
      destination_type      = "volume"
      volume_size           = 30
      boot_index            = 0
      volume_type           = "STANDARD"
      delete_on_termination = true
    },  
  ]

  vm_networks = [
    {
      uuid        = openstack_networking_network_v2.private_network.id
      fixed_ip_v4 = "172.16.5.11"
    },
  ]
}

