# Single Environment Configuration
stack_name           = "k8s-ha"
cloud_name           = "openstack"
clouds_yaml_path     = "../secrets/clouds.yaml"
ssh_private_key_file = "../secrets/private_key.pem"
key_pair_name        = "FASE_CLOUD_DEV"

# Cluster Topology
controlplane_count = 3
worker_count       = 3
lb_count           = 1

# Node Flavors
controlplane_flavor = "l3.nano"
worker_flavor       = "l3.tiny"
lb_flavor           = "l3.nano"

# Load Balancer Floating IP
lb_fip_address = "130.246.81.27"
