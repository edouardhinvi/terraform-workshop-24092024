variable myregion {
  default = "GA11" # Replace with the OS_REGION_NAME environment variable content
}

# Creating a private network
resource "ovh_cloud_project_network_private" "private_network" {
  service_name  = var.service_name
  name          = "backend" # Network name
  regions       = [var.myregion] 
  provider      = ovh.ovh # Provider name
  vlan_id       = 42 # vRack vlan ID
  depends_on    = [ovh_vrack_cloudproject.vcp] # Depends on vRack being associated with the cloud project
}

# Creating a private subnet
resource "ovh_cloud_project_network_private_subnet" "private_subnet" {
  # ID for the ovh_cloud_network_private resource named private_network
  network_id    = ovh_cloud_project_network_private.private_network.id
  service_name  = var.service_name
  region        = var.myregion
  network       = "192.168.42.0/24" # Subnet IP
  start         = "192.168.42.2" # First IP of the subnet
  end           = "192.168.42.200" # Last IP of the subnet
  dhcp          = false # Disabling DHCP
  provider      = ovh.ovh # Provider name
  no_gateway    = true # No default gateway
}

# Search for the latest Archlinux image
data "openstack_images_image_v2" "archlinux" {
  name          = "Archlinux" # Image name
  most_recent   = true # Limits search to the most recent
  provider      = openstack.ovh # Provider name
}

# List of possible private IP addresses for front-ends
variable "front_private_ip" {
  type          = list(any)
  default       = ["192.168.42.2", "192.168.42.3"]
}

# Create 2 instances with 2 network interfaces
resource "openstack_compute_instance_v2" "front" {
  count           = length(var.front_private_ip) # Number of instances to create
  provider        = openstack.ovh # Provider name
  name            = "front" # Instance name
  key_pair        = openstack_compute_keypair_v2.test_keypair.name
  flavor_name     = "d2-2" # Instance type name
  image_id        = data.openstack_images_image_v2.archlinux.id # Instance image ID
  security_groups = ["default"] # Adds the instance to the security group
  network {
    name = "Ext-Net" # Public network interface name
  }
  network {
    # Private network interface name
    name = ovh_cloud_project_network_private.private_network.name
    # IP address taken from the list defined earlier
    fixed_ip_v4 = element(var.front_private_ip, count.index)
  }
  depends_on = [ovh_cloud_project_network_private_subnet.private_subnet] # Depends on private network
}

# Create an attachable storage device for the backup (volume)
resource "openstack_blockstorage_volume_v2" "backup" {
  name     = "backup_disk" # Name of storage device
  size     = 10 # Size
  provider = openstack.ovh # Provider name
}

# Create an instance with a network interface and storage device
resource "openstack_compute_instance_v2" "back" {
  provider        = openstack.ovh # Provider name
  name            = "back" # Instance name
  key_pair        = openstack_compute_keypair_v2.test_keypair.name
  flavor_name     = "d2-2" # Instance type name
  image_id        = data.openstack_images_image_v2.archlinux.id # Instance image ID
  security_groups = ["default"] # Adds the instance to the security group
  network {
    name        = ovh_cloud_project_network_private.private_network.name # Private network name
    fixed_ip_v4 = "192.168.42.150" # Private IP address chosen arbitrarily
  }
  # Bootable storage device containing the OS
  block_device {
    uuid                  = data.openstack_images_image_v2.archlinux.id # Instance image ID
    source_type           = "image" # Source type
    destination_type      = "local" # Destination
    volume_size           = 10 # Size
    boot_index            = 0  # Boot order
    delete_on_termination = true  # The device will be deleted when the instance is deleted
  }
  # Storage device
  block_device {
    source_type           = "blank" # Source type
    destination_type      = "volume" # Destination
    volume_size           = 20 # Size
    boot_index            = 1 # Boot order
    delete_on_termination = true # The device will be deleted when the instance is deleted
  }
  # Previously created storage device
  block_device {
    uuid                  = openstack_blockstorage_volume_v2.backup.id # Storage Device ID
    source_type           = "volume" # Source type
    destination_type      = "volume" # Destination
    boot_index            = 2 # Boot order
    delete_on_termination = true # The device will be deleted when the instance is deleted
  }
  depends_on = [ovh_cloud_project_network_private_subnet.private_subnet] # Depends on private network
}
