# Setup Kubeadm master and worker setup

## Setup Master Node
```bash
sudo -i
bash <(curl -s https://raw.githubusercontent.com/thakurnishu/homelab/refs/heads/proxmox/homelab-setup/kubeadm/master.sh)
```

## Setup Worker Node
```bash
sudo -i
bash <(curl -s https://raw.githubusercontent.com/thakurnishu/homelab/refs/heads/proxmox/homelab-setup/kubeadm/worker.sh)
```
