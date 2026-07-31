# ==============================================================================
# 1. NETWORK & DATA SOURCES
# ==============================================================================
# (Using Shared Internal Network)
# Retrieve existing "Internal" network
data "openstack_networking_network_v2" "internal" {
  name = "Internal"
}
data "openstack_networking_network_v2" "external" {
  name = "External"
}

# Create Dedicated LB Network
resource "openstack_networking_network_v2" "lb_network" {
  name           = "${var.stack_name}-ha-lb-network"
  admin_state_up = "true"
}

# Create Dedicated LB Subnet
resource "openstack_networking_subnet_v2" "lb_subnet" {
  name            = "${var.stack_name}-ha-lb-subnet"
  network_id      = openstack_networking_network_v2.lb_network.id
  cidr            = var.lb_network_cidr
  ip_version      = 4
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}

# Router to bridge the new subnet to the outside world
resource "openstack_networking_router_v2" "lb_router" {
  name                = "${var.stack_name}-ha-lb-router"
  external_network_id = data.openstack_networking_network_v2.external.id
}

# Attach the Subnet to the Router
resource "openstack_networking_router_interface_v2" "lb_router_interface" {
  router_id = openstack_networking_router_v2.lb_router.id
  subnet_id = openstack_networking_subnet_v2.lb_subnet.id
}

# ==============================================================================
# 2. SECURITY GROUPS
# ==============================================================================

# Retrieve existing "default" security group (still needed for SSH if using default keys)
data "openstack_networking_secgroup_v2" "default" {
  name = "default"
}

# Common Security Group (All Nodes)
# ------------------------------------------------------------------------------
resource "openstack_networking_secgroup_v2" "k8s_common" {
  name                 = "${var.stack_name}-ha-k8s-common"
  description          = "Common rules for all K8s nodes (SSH, API, Cilium, Internal)"
  delete_default_rules = true
}

# All Ingress and Egress are allowed because that's the default behavior for current CAPI implementation
# 1. Allow All Ingress (Trusted Internal Network)
resource "openstack_networking_secgroup_rule_v2" "ingress_all" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_common.id
  description       = "Allow All Ingress"
}

# Egress Rule - Allow all outbound traffic
resource "openstack_networking_secgroup_rule_v2" "common_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_common.id
}

# ==============================================================================
# 3. COMPUTE INSTANCES
# ==============================================================================

# Create Control Plane Instances
resource "openstack_compute_instance_v2" "control_plane" {
  count       = var.controlplane_count
  name        = "${var.stack_name}-ha-controlplane-${count.index + 1}"
  image_name  = "ubuntu-noble-24.04-nogui"
  flavor_name = var.controlplane_flavor
  key_pair    = var.key_pair_name

  network {
    uuid = data.openstack_networking_network_v2.internal.id
    name = data.openstack_networking_network_v2.internal.name
  }

  security_groups = [
    openstack_networking_secgroup_v2.k8s_common.name,
    data.openstack_networking_secgroup_v2.default.name
  ]

  tags = ["managed-by=terraform"]
}

# Create Worker Instances
resource "openstack_compute_instance_v2" "worker" {
  count       = var.worker_count
  name        = "${var.stack_name}-ha-worker-${count.index + 1}"
  image_name  = "ubuntu-noble-24.04-nogui"
  flavor_name = var.worker_flavor
  key_pair    = var.key_pair_name

  network {
    uuid = data.openstack_networking_network_v2.internal.id
    name = data.openstack_networking_network_v2.internal.name
  }

  security_groups = [
    openstack_networking_secgroup_v2.k8s_common.name,
    data.openstack_networking_secgroup_v2.default.name
  ]


  tags = ["managed-by=terraform"]
}

# Create HAProxy Load Balancer Instance
resource "openstack_compute_instance_v2" "haproxy_lb" {
  count       = var.lb_count
  name        = "${var.stack_name}-ha-haproxy-lb-${count.index + 1}"
  image_name  = "ubuntu-noble-24.04-nogui"
  flavor_name = var.lb_flavor
  key_pair    = var.key_pair_name

  network {
    uuid = data.openstack_networking_network_v2.internal.id
    name = data.openstack_networking_network_v2.internal.name
  }

  network {
    uuid = openstack_networking_network_v2.lb_network.id
  }

  security_groups = [
    openstack_networking_secgroup_v2.k8s_common.name,
    data.openstack_networking_secgroup_v2.default.name
  ]


  tags = ["managed-by=terraform"]

  depends_on = [
    openstack_networking_subnet_v2.lb_subnet
  ]
}

# ==============================================================================
# 4. FLOATING IP BINDING (HAProxy Application LB)
# ==============================================================================

data "openstack_networking_floatingip_v2" "app_fip" {
  address = var.lb_fip_address
}

resource "openstack_compute_floatingip_associate_v2" "lb_fip_assoc" {
  count       = var.lb_count
  floating_ip = data.openstack_networking_floatingip_v2.app_fip.address
  instance_id = openstack_compute_instance_v2.haproxy_lb[count.index].id
  fixed_ip    = openstack_compute_instance_v2.haproxy_lb[count.index].network[1].fixed_ip_v4

  depends_on = [
    openstack_networking_router_interface_v2.lb_router_interface
  ]
}

# ==============================================================================
# 5. OUTPUTS
# ==============================================================================

# Output IPs for easy access
output "control_plane_ips" {
  value = openstack_compute_instance_v2.control_plane[*].access_ip_v4
}

output "worker_ips" {
  value = openstack_compute_instance_v2.worker[*].access_ip_v4
}

output "haproxy_lb_private_ips" {
  value = openstack_compute_instance_v2.haproxy_lb[*].access_ip_v4
}

# ==============================================================================
# 6. ANSIBLE INVENTORY GENERATION
# ==============================================================================

# 1. Initial Control Plane Inventory
resource "local_file" "inventory_init_cp" {
  filename = "../ansible/inventory_controlplane_init.ini"
  content  = <<EOT
[controlplane]
${openstack_compute_instance_v2.control_plane[0].access_ip_v4}

[loadbalancer]
${data.openstack_networking_floatingip_v2.app_fip.address}

[all:vars]
node_prefix=${var.stack_name}-
ansible_ssh_private_key_file=${var.ssh_private_key_file}
ansible_user=ubuntu
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
control_plane_endpoint=${openstack_compute_instance_v2.control_plane[0].access_ip_v4}
clouds_yaml_path=${var.clouds_yaml_path}
cloud_name=openstack
EOT
}

# 2. Additional Control Planes Inventory (Joiners)
resource "local_file" "inventory_join_cp" {
  filename = "../ansible/inventory_controlplane_join.ini"
  content  = <<EOT
[controlplane]
%{for ip in openstack_compute_instance_v2.control_plane[*].access_ip_v4~}
${ip}
%{endfor~}

[loadbalancer]
${data.openstack_networking_floatingip_v2.app_fip.address}

[all:vars]
node_prefix=${var.stack_name}-
ansible_ssh_private_key_file=${var.ssh_private_key_file}
ansible_user=ubuntu
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
control_plane_endpoint=${openstack_compute_instance_v2.control_plane[0].access_ip_v4}
clouds_yaml_path=${var.clouds_yaml_path}
cloud_name=openstack
EOT
}

# 3. Worker Nodes Inventory
resource "local_file" "inventory_workers" {
  filename = "../ansible/inventory_workers.ini"
  content  = <<EOT
[controlplane]
${openstack_compute_instance_v2.control_plane[0].access_ip_v4}

[workers]
%{for ip in openstack_compute_instance_v2.worker[*].access_ip_v4~}
${ip}
%{endfor~}

[loadbalancer]
${data.openstack_networking_floatingip_v2.app_fip.address}

[all:vars]
node_prefix=${var.stack_name}-
ansible_ssh_private_key_file=${var.ssh_private_key_file}
ansible_user=ubuntu
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
control_plane_endpoint=${openstack_compute_instance_v2.control_plane[0].access_ip_v4}
clouds_yaml_path=${var.clouds_yaml_path}
cloud_name=openstack
EOT
}

# 4. Common Inventory (All Nodes)
resource "local_file" "inventory_all" {
  filename = "../ansible/inventory_all.ini"
  content  = <<EOT
[controlplane]
%{for ip in openstack_compute_instance_v2.control_plane[*].access_ip_v4~}
${ip}
%{endfor~}

[workers]
%{for ip in openstack_compute_instance_v2.worker[*].access_ip_v4~}
${ip}
%{endfor~}

[loadbalancer]
${data.openstack_networking_floatingip_v2.app_fip.address}

[all:vars]
node_prefix=${var.stack_name}-
ansible_ssh_private_key_file=${var.ssh_private_key_file}
ansible_user=ubuntu
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
control_plane_endpoint=${openstack_compute_instance_v2.control_plane[0].access_ip_v4}
clouds_yaml_path=${var.clouds_yaml_path}
cloud_name=openstack
EOT
}
