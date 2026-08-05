# Step 04: Joining Secondary Control Plane Nodes

**Playbook Reference:** `ansible/playbook_controlplane_join.yaml`  
**Target Nodes:**
1. **Generate Credentials:** `controlplane-0`
2. **Execute Join Command:** Secondary Control Plane Nodes (`controlplane-1`, `controlplane-2`)

To achieve High Availability (HA), our cluster uses 3 Control Plane nodes. In this step, we generate a fresh join token and certificate decryption key on `controlplane-0`, and then use those credentials to join `controlplane-1` and `controlplane-2` to the cluster.

---

## 🔌 Before You Begin: Finding IPs & Connecting via SSH

1. **Find your VM IP addresses:** Check your Ansible inventory file from the project root to get the IP address of `controlplane-1` and `controlplane-2`:
   ```bash
   cat ansible/inventory_all.ini
   ```
2. **Connect via SSH:** SSH into `controlplane-1` and `controlplane-2` in separate terminal tabs:
   ```bash
   ssh -i secrets/private_key.pem ubuntu@<CONTROLPLANE_1_OR_2_IP>
   ```
3. **Resetting a Node:** If a node fails to join, clean it by running:
   ```bash
   sudo kubeadm reset -f
   sudo rm -rf /etc/kubernetes/admin.conf /etc/kubernetes/pki $HOME/.kube/config
   ```

---

## 1. Generate Join Credentials (on `controlplane-0`)

- **What this step does:** Re-uploads encrypted Kubernetes control plane TLS certificates to the cluster secret store, prints the temporary decryption key (`--certificate-key`), and generates a fresh `kubeadm join` command with `--control-plane`.
- **Why we are doing it:** Control plane certificates uploaded during `kubeadm init` expire from the secret store after 2 hours for security. Re-uploading them ensures valid credentials are available. 
  - Why `--control-plane` and `--certificate-key`? A normal worker node only needs the API endpoint, token, and CA certificate hash. A secondary control plane node must also download and decrypt the Kubernetes root CA, API server private keys, ServiceAccount signing keys, and join the `etcd` raft consensus cluster using `--certificate-key`.

Execute these commands **on `controlplane-0`**:

```bash
# 1. Re-upload TLS certificates to the cluster secret store and capture the decryption key
CERT_KEY=$(sudo kubeadm init phase upload-certs --upload-certs | tail -n 1)
echo "Certificate Key: ${CERT_KEY}"
```
```bash
# 2. Generate the base join command with a fresh token
BASE_JOIN_CMD=$(sudo kubeadm token create --print-join-command)
echo "Base Join Command: ${BASE_JOIN_CMD}"
```
```bash
# 3. Print the full HA Control Plane Join Command
echo -e "\n=========================================================================="
echo "Run the following command with 'sudo' on controlplane-1 and controlplane-2:"
echo "=========================================================================="
echo "${BASE_JOIN_CMD} --control-plane --certificate-key ${CERT_KEY}"
echo "=========================================================================="
```

---

## 2. Join Secondary Control Planes (on `controlplane-1` and `controlplane-2`)

- **What this step does:** Verifies that `/etc/kubernetes/kubelet.conf` does not already exist, queries the OpenStack Metadata service for the VM hostname, and executes the HA `kubeadm join --control-plane` command.
- **Why we are doing it:** Checking `/etc/kubernetes/kubelet.conf` prevents running `kubeadm join` twice on the same node. Appending `--node-name="${OS_HOSTNAME}"` ensures `controlplane-1` and `controlplane-2` register under their OpenStack instance names, preventing identity mismatches in `etcd` and API TLS certificates.

SSH into **`controlplane-1`** and **`controlplane-2`** and run the following commands:

```bash
# 1. Verify the node has not already joined the cluster
if [ -f /etc/kubernetes/kubelet.conf ]; then
  echo "Node is already part of a cluster! Aborting."
else
  # 2. Fetch the true OpenStack instance hostname
  OS_HOSTNAME=$(curl -s http://169.254.169.254/latest/meta-data/hostname | cut -d. -f1)
  echo "Joining node as: ${OS_HOSTNAME}"
```
```bash
  # 3. Execute the join command from Step 1 (replace the example below with your output from controlplane-0)
  # IMPORTANT: Append --node-name="${OS_HOSTNAME}" to ensure hostname consistency!
  sudo kubeadm join 10.0.10.100:6443 \
    --token <YOUR_TOKEN> \
    --discovery-token-ca-cert-hash sha256:<YOUR_HASH> \
    --control-plane \
    --certificate-key <YOUR_CERT_KEY> \
    --node-name="${OS_HOSTNAME}"
fi
```

---

## 3. Configure `kubectl` on Secondary Control Plane Nodes (Optional)

- **What this step does:** Creates the `$HOME/.kube` directory on `controlplane-1` or `controlplane-2`, copies `/etc/kubernetes/admin.conf` to `$HOME/.kube/config`, and assigns ownership to `ubuntu`.
- **Why we are doing it:** Having `kubectl` configured on every control plane node provides administrative redundancy. If `controlplane-0` is unreachable, you can SSH into any secondary control plane node and manage the cluster locally.

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify local kubectl works
kubectl get nodes -o wide
```

---

## ✅ Verification Check

- **What this check does:** Lists all cluster nodes and checks their roles and readiness status.
- **Why we are doing it:** Confirms that all 3 Control Plane nodes (`controlplane-0`, `controlplane-1`, `controlplane-2`) have successfully joined the `etcd` cluster and API server consensus pool in the `Ready` state.

```bash
kubectl get nodes -o wide
```

You should see **all 3 Control Plane nodes (`controlplane-0`, `controlplane-1`, `controlplane-2`)** listed in the `Ready` state with `control-plane` roles:

```text
NAME             STATUS   ROLES           AGE   VERSION   INTERNAL-IP
controlplane-0   Ready    control-plane   15m   v1.35.0   10.0.10.10
controlplane-1   Ready    control-plane   2m    v1.35.0   10.0.10.11
controlplane-2   Ready    control-plane   1m    v1.35.0   10.0.10.12
```

---

### [Next Step: Joining Worker Nodes &rarr;](05-worker-join.md)
