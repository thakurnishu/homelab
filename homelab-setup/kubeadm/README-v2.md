# Setup Kubeadm master and worker setup

## Setup Master Node
Setup environment Variable in master node:
```bash
cat <<EOF > k8s-env
POD_NETWORK_CIDR="10.244.0.0/16"
SERVICE_NETWORK_CIDR="10.96.0.0/12"
KUBE_VERSION="1.34.2"
KUBE_MINOR_VERSION="1.34"
CONTAINERD_VERSION="2.2.0"
RUNC_VERSION="1.4.0"
CNI_VERSION="1.9.0"
CALICO_VERSION="3.31.2"

MASTER_NODE_INTERNAL_IP=""
MASTER_NODE_NAME=""
EOF
```
Then run:
```bash
sudo -i
bash <(curl -s https://raw.githubusercontent.com/thakurnishu/homelab/refs/heads/proxmox/homelab-setup/kubeadm/master-v2.sh)
```

## Setup Worker Node
Setup environment Variable in master node:
```bash
cat <<EOF > k8s-env
POD_NETWORK_CIDR="10.244.0.0/16"
SERVICE_NETWORK_CIDR="10.96.0.0/12"
KUBE_VERSION="1.34.2"
KUBE_MINOR_VERSION="1.34"
CONTAINERD_VERSION="2.2.0"
RUNC_VERSION="1.4.0"
CNI_VERSION="1.9.0"
CALICO_VERSION="3.31.2"

WORKER_NODE_INTERNAL_IP=""
WORKER_NODE_NAME=""
EOF
```
Then run:
```bash
sudo -i
bash <(curl -s https://raw.githubusercontent.com/thakurnishu/homelab/refs/heads/proxmox/homelab-setup/kubeadm/worker-v2.sh)
```
