# Step 05: Joining Worker Nodes

**Playbook Reference:** `ansible/playbook_worker_join.yaml`  
**Target Nodes:**
1. **Generate Token:** `controlplane-0`
2. **Execute Join Command:** Worker Nodes (`worker-0`, `worker-1`, `worker-2`)

Worker nodes host your application Pods, Cilium CNI routing rules, and Longhorn distributed storage volumes. In this step, we generate a worker join command from `controlplane-0` and join all 3 worker nodes to the cluster.

---

## 🔌 Before You Begin: Finding IPs & Connecting via SSH

1. **Find your VM IP addresses:** Check your Ansible inventory file from the project root to get the IP addresses of `worker-0`, `worker-1`, and `worker-2`:
   ```bash
   cat ansible/inventory_all.ini
   ```
2. **Connect via SSH:** SSH into each worker node in separate terminal tabs:
   ```bash
   ssh -i secrets/private_key.pem ubuntu@<WORKER_0_1_OR_2_IP>
   ```
3. **Resetting a Node:** If a worker node fails to join, clean it by running:
   ```bash
   sudo kubeadm reset -f
   sudo rm -rf /etc/kubernetes/admin.conf /etc/kubernetes/pki $HOME/.kube/config
   ```

---

## 1. Generate Worker Join Command (on `controlplane-0`)

- **What this step does:** Creates a temporary Kubernetes API authentication token and outputs a formatted `kubeadm join` command containing the API server endpoint, token, and root CA certificate SHA-256 hash.
- **Why we are doing it:** Worker nodes do not need `--control-plane` flags or certificate decryption keys because they do not host `etcd` or API servers. They only need a trusted token and CA hash to authenticate with the Load Balancer VIP and register their `kubelet`.

Execute this command **on `controlplane-0`**:

```bash
# Generate and print a fresh worker join command
WORKER_JOIN_CMD=$(sudo kubeadm token create --print-join-command)

echo "=========================================================================="
echo "Run the following command with 'sudo' on worker-0, worker-1, and worker-2:"
echo "=========================================================================="
echo "${WORKER_JOIN_CMD}"
echo "=========================================================================="
```

> [!NOTE]
> Join tokens expire after 24 hours. You can generate a new token at any time by running `sudo kubeadm token create --print-join-command` on any control plane node.

---

## 2. Verify Longhorn Storage Directory (on Worker Nodes)

- **What this step does:** Checks that directory `/data0` exists on `worker-0`, `worker-1`, and `worker-2` with root ownership and `755` permissions.
- **Why we are doing it:** Longhorn distributed storage relies on `/data0` as a hostPath mount for data replication across worker nodes. If this folder is missing when worker nodes enroll, Longhorn pod deployments will fail with volume mounting errors.

Before joining, verify that `/data0` was created during **Step 01** on each worker node:

```bash
ls -ld /data0
```

You should see root ownership and permissions `rwxr-xr-x` (`755`):
```text
drwxr-xr-x 2 root root 4096 Jul 30 11:00 /data0
```

If `/data0` is missing, create it now:
```bash
sudo mkdir -p /data0 && sudo chmod 755 /data0 && sudo chown root:root /data0
```

---

## 3. Join Worker Nodes (`worker-0`, `worker-1`, `worker-2`)

- **What this step does:** Checks that `/etc/kubernetes/kubelet.conf` is absent, queries the OpenStack Metadata API for the instance hostname, and runs the worker `kubeadm join` command with `--node-name`.
- **Why we are doing it:** Enrolls the worker VM into the Kubernetes cluster. Explicitly setting `--node-name="${OS_HOSTNAME}"` guarantees that the worker registers in the Kubernetes API under its true cloud hostname (`worker-0`, `worker-1`, `worker-2`), matching HAProxy backend rules and Longhorn node topologies.

SSH into **`worker-0`**, **`worker-1`**, and **`worker-2`** and execute the following:

```bash
# 1. Verify the node has not already joined the cluster
if [ -f /etc/kubernetes/kubelet.conf ]; then
  echo "Node is already part of a cluster! Aborting."
else
  # 2. Fetch the true OpenStack instance hostname
  OS_HOSTNAME=$(curl -s http://169.254.169.254/latest/meta-data/hostname | cut -d. -f1)
  echo "Joining worker as: ${OS_HOSTNAME}"

  # 3. Execute the join command from Step 1 (replace below with your output from controlplane-0)
  # IMPORTANT: Append --node-name="${OS_HOSTNAME}" to ensure hostname consistency!
  sudo kubeadm join 10.0.10.100:6443 \
    --token <YOUR_TOKEN> \
    --discovery-token-ca-cert-hash sha256:<YOUR_HASH> \
    --node-name="${OS_HOSTNAME}"
fi
```

---

## 4. Verify Node Enrollment (from `controlplane-0`)

- **What this step does:** Runs `kubectl get nodes -o wide` from the control plane to list all enrolled cluster nodes and verify their operational state.
- **Why we are doing it:** Confirms that all 3 Control Planes and 3 Worker Nodes have registered with `kube-apiserver` and that Cilium eBPF CNI has successfully initialized network interfaces across all 6 nodes, transitioning them to `Ready`.

Return to `controlplane-0` (or your workstation with `kubectl` configured) and verify all nodes:

```bash
kubectl get nodes -o wide
```

Within 1–2 minutes, as Cilium configures eBPF interfaces on each worker, **all 6 nodes** should show `STATUS: Ready`:

```text
NAME             STATUS   ROLES           AGE   VERSION   INTERNAL-IP   OS-IMAGE           KERNEL-VERSION
controlplane-0   Ready    control-plane   25m   v1.35.0   10.0.10.10    Ubuntu 24.04 LTS   6.8.0-xx-generic
controlplane-1   Ready    control-plane   12m   v1.35.0   10.0.10.11    Ubuntu 24.04 LTS   6.8.0-xx-generic
controlplane-2   Ready    control-plane   11m   v1.35.0   10.0.10.12    Ubuntu 24.04 LTS   6.8.0-xx-generic
worker-0         Ready    <none>          3m    v1.35.0   10.0.10.20    Ubuntu 24.04 LTS   6.8.0-xx-generic
worker-1         Ready    <none>          2m    v1.35.0   10.0.10.21    Ubuntu 24.04 LTS   6.8.0-xx-generic
worker-2         Ready    <none>          1m    v1.35.0   10.0.10.22    Ubuntu 24.04 LTS   6.8.0-xx-generic
```

---

### [Next Step: Verification & Troubleshooting &rarr;](06-verification-and-troubleshooting.md)
