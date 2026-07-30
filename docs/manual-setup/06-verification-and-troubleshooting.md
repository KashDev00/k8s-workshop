# Step 06: Verification & Troubleshooting

**Target Nodes:** Any Control Plane Node (`controlplane-0`, `controlplane-1`, `controlplane-2`) or Local Workstation with `kubectl` configured.

Congratulations! Your High Availability Kubernetes cluster is now manually assembled. Use this guide to verify that all networking, observability, and storage components are functioning correctly, and to troubleshoot common deployment errors.

---

## 🔌 Before You Begin: Connecting to `controlplane-0`

Run the verification commands below from **`controlplane-0`** (or any node/workstation where you configured `kubectl` in Step 03):

```bash
# 1. Find controlplane-0 IP address
cat ansible/inventory_all.ini

# 2. SSH into controlplane-0
ssh -i secrets/private_key.pem ubuntu@<CONTROLPLANE_0_IP_ADDRESS>
```

---

## 1. Complete Cluster Verification

### 1.1 Check All Nodes
- **What this step does:** Queries the Kubernetes API server for the list of all nodes, displaying their status, assigned roles, age, Kubernetes version, and internal OpenStack IP addresses.
- **Why we are doing it:** Verifies that all 6 provisioned VMs (3 Control Planes + 3 Workers) have joined the cluster and transitioned to the `Ready` state.

```bash
kubectl get nodes -o wide
```

Expected Output:
```text
NAME             STATUS   ROLES           AGE   VERSION   INTERNAL-IP
controlplane-0   Ready    control-plane   30m   v1.35.0   10.0.10.10
controlplane-1   Ready    control-plane   18m   v1.35.0   10.0.10.11
controlplane-2   Ready    control-plane   16m   v1.35.0   10.0.10.12
worker-0         Ready    <none>          10m   v1.35.0   10.0.10.20
worker-1         Ready    <none>          8m    v1.35.0   10.0.10.21
worker-2         Ready    <none>          7m    v1.35.0   10.0.10.22
```

### 1.2 Check System Pods & eBPF Kube-Proxy Replacement
- **What this step does:** Lists all system Pods running in the `kube-system` namespace and runs `cilium status` inside a Cilium agent pod to inspect the eBPF datapath.
- **Why we are doing it:** Confirms that critical control plane workloads (`etcd`, `coredns`, `kube-apiserver`, `cilium`) are `Running` and proves that standard `kube-proxy` was successfully omitted and replaced by Cilium's eBPF engine (`KubeProxyReplacement: True`).

```bash
# 1. Check pods in kube-system
kubectl get pods -n kube-system -o wide

# 2. Check Cilium eBPF KubeProxyReplacement status
kubectl -n kube-system exec -it -l k8s-app=cilium -- cilium status --brief
```

Expected output should confirm `KubeProxyReplacement: True`:
```text
Cilium:             OK
Operator:           OK
Hubble Relay:       OK
ClusterMesh:        disabled
```

### 1.3 Verify Kubernetes Gateway API Support
- **What this step does:** Checks the cluster for registered `GatewayClass` resources.
- **Why we are doing it:** Confirms that the Gateway API v1.6.1 Custom Resource Definitions (CRDs) applied in Step 03 were detected by Cilium and that Cilium has successfully registered itself as the default Ingress Controller (`io.cilium/gateway-controller`).

```bash
kubectl get gatewayclasses
```

Expected Output:
```text
NAME     CONTROLLER                     ACCEPTED   AGE
cilium   io.cilium/gateway-controller   True       25m
```

### 1.4 Test Metrics Server
- **What this step does:** Queries the `metrics.k8s.io` API to display live CPU and memory utilization across all cluster nodes.
- **Why we are doing it:** Verifies that the Metrics Server is scraping node `kubelets` without TLS or DNS hostname resolution errors, enabling Horizontal Pod Autoscalers and resource monitoring.

```bash
kubectl top nodes
```

Expected Output:
```text
NAME             CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%   
controlplane-0   140m         7%     1680Mi          42%
worker-0         65m          3%     920Mi           23%
...
```

---

## 2. Troubleshooting Common Issues

### 2.1 Node Stuck in `NotReady` State
* **Symptom:** A node appears in `kubectl get nodes` as `NotReady` for more than 5 minutes.
* **What this fix does:** Checks IPv4 forwarding kernel settings and inspects logs for the Cilium CNI pod running on that node.
* **Why we are doing it:** A node remains `NotReady` if its Container Network Interface (CNI) cannot initialize virtual bridge interfaces or if the Linux kernel blocks IP forwarding between namespaces.

```bash
# On the affected node:
sysctl net.ipv4.ip_forward
lsmod | grep -E 'overlay|br_netfilter'

# On controlplane-0:
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
kubectl logs -n kube-system -l k8s-app=cilium --tail=50
```

---

### 2.2 IP Mismatch or Certificate SAN Errors (`kubeadm init` failed)
* **Symptom:** API server certificates reject connections, or you used the wrong `FINAL_CP_ENDPOINT` during `kubeadm init`.
* **What this fix does:** Reverts `kubeadm` initialization state, stops core containers, and deletes generated TLS certificates and config files.
* **Why we are doing it:** Kubernetes control plane certificates bake the IP address and hostname into immutable Subject Alternative Names (SANs). If an incorrect Load Balancer VIP was used, you must wipe the generated PKI directory before re-running `kubeadm init`.

```bash
# 1. Reset kubeadm state
sudo kubeadm reset -f

# 2. Clean up residual configs and certificates
sudo rm -rf /etc/kubernetes/admin.conf /etc/kubernetes/pki
rm -f $HOME/.kube/config

# 3. Re-run Step 03 with the correct endpoint variable
```

---

### 2.3 Load Balancer Floating IP Timeout (Asymmetric Routing)
* **Symptom:** The HAProxy Load Balancer internal IP is reachable, but its OpenStack Floating IP drops connections.
* **What this fix does:** Inspects Linux IP routing rules and applies the custom Netplan policy routing table (`table 102`).
* **Why we are doing it:** When a VM has multiple network interfaces or default routes assigned by OpenStack DHCP, return packets for external Floating IP connections can leave through the wrong gateway interface. Policy routing forces reply traffic out through the designated OpenStack subnet gateway (`10.0.50.1`).

```bash
# Verify policy routing rule exists for table 102
ip rule show

# If missing, re-apply Netplan
sudo netplan apply
```

---

### 2.4 Containerd Cgroups Mismatch (`SystemdCgroup = false`)
* **Symptom:** `kubelet` service crashes repeatedly with cgroup driver errors in `journalctl -u kubelet`.
* **What this fix does:** Edits `/etc/containerd/config.toml` to enable systemd cgroups and restarts both containerd and kubelet.
* **Why we are doing it:** Aligns the container runtime's cgroup driver (`systemd`) with Ubuntu's init manager and `kubelet`, resolving resource tracking conflicts that crash node agents.

```bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

---

## 🎉 Tutorial Complete!

You have successfully built an enterprise-grade High Availability Kubernetes cluster on OpenStack manually. You are now ready to deploy workloads, Ingress Gateways, and Longhorn persistent volumes!

* **[&larr; Back to Documentation Overview](README.md)**
