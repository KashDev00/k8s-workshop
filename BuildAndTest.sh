#!/bin/bash

cd initInfra
terraform destroy -auto-approve || true
terraform apply -auto-approve

cd ..
cd ansible
echo "Waiting for nodes to be reachable..."
until ansible all -m ping -i inventory_all.ini; do
    echo "Nodes not reachable yet, retrying in 5 seconds..."
    sleep 5
done

ansible-playbook -i inventory_all.ini playbook_common.yaml
ansible-playbook -i inventory_controlplane_init.ini playbook_controlplane_init.yaml
ansible-playbook -i inventory_controlplane_join.ini playbook_controlplane_join.yaml
ansible-playbook -i inventory_workers.ini playbook_worker_join.yaml
ansible-playbook -i inventory_all.ini playbook_lb.yaml


cd ..
export KUBECONFIG=./kubeconfigs/stfc-cloud.kubeconfig
echo "Deploying Gateway infrastructure..."
kubectl apply -f gateway.yaml

echo "Waiting for Cilium to create the Gateway service..."
until kubectl get svc cilium-gateway-gateway &>/dev/null && [ -n "$(kubectl get svc cilium-gateway-gateway -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)" ]; do
    sleep 3
done

echo "Pinning Gateway NodePort to 30080..."
kubectl patch svc cilium-gateway-gateway --type='json' \
  -p='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30080}]'

echo "Final Verification:"
kubectl get nodes -o wide
kubectl get gateway,httproute,svc