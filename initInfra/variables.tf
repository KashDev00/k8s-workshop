variable "cloud_name" {
  description = "The name of the cloud in clouds.yaml to use"
  type        = string
  default     = "openstack"
}

variable "clouds_yaml_path" {
  description = "Path to the clouds.yaml file"
  type        = string
  default     = "../secrets/clouds.yaml"
}

variable "stack_name" {
  description = "Stack name for resource naming and config lookup"
  type        = string
}

variable "controlplane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "ssh_private_key_file" {
  description = "Path to the SSH private key file for Ansible"
  type        = string
  default     = "../secrets/private_key.pem"
}

variable "key_pair_name" {
  description = "Name of the OpenStack SSH key pair"
  type        = string
}

variable "controlplane_flavor" {
  description = "Flavor name for control plane nodes"
  type        = string
  default     = "l3.nano"
}

variable "worker_flavor" {
  description = "Flavor name for worker nodes"
  type        = string
  default     = "l3.nano"
}

variable "lb_network_cidr" {
  description = "The CIDR block for the dedicated LoadBalancer network"
  type        = string
  default     = "10.0.50.0/24"
}

variable "lb_count" {
  description = "Number of HAProxy load balancer nodes"
  type        = number
  default     = 1
}

variable "lb_flavor" {
  description = "Flavor name for HAProxy load balancer nodes"
  type        = string
  default     = "l3.nano"
}

variable "lb_fip_address" {
  description = "The Floating IP address to assign to the application load balancer"
  type        = string
}
