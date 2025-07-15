#!/bin/bash

home_dir="homelab-setup"
git_user="thakurnishu"
git_repo="homelab"

containerd_version="2.0.4"
runc_version="1.3.0"
cni_version="1.6.2"
k8s_version='1.31'
calico_version='3.29.3'

# Update
sudo apt update

# Net
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl --system

# containerd
sudo wget -O /tmp/containerd-${containerd_version}-linux-amd64.tar.gz \
  https://github.com/containerd/containerd/releases/download/v${containerd_version}/containerd-${containerd_version}-linux-amd64.tar.gz
sudo tar Cxzvf /usr/local /tmp/containerd-${containerd_version}-linux-amd64.tar.gz

sudo mkdir -p /usr/local/lib/systemd/system
sudo mkdir -p /etc/containerd
sudo cp ${home_dir}/files/containerd/containerd.service /usr/local/lib/systemd/system/containerd.service
sudo cp ${home_dir}/files/containerd/config.toml /etc/containerd/config.toml
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
sudo systemctl restart containerd

# runc
sudo wget -O /tmp/runc.amd64 https://github.com/opencontainers/runc/releases/download/v${runc_version}/runc.amd64
sudo install -m 755 /tmp/runc.amd64 /usr/local/sbin/runc

# CNI
sudo wget -O /tmp/cni-plugins-linux-amd64-v${cni_version}.tgz \
  https://github.com/containernetworking/plugins/releases/download/v${cni_version}/cni-plugins-linux-amd64-v${cni_version}.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin /tmp/cni-plugins-linux-amd64-v${cni_version}.tgz

# FluxCD
curl -s https://fluxcd.io/install.sh | sudo bash

# kubectl, kubeadm, kubelet
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg open-iscsi nfs-common

# LongHorn Requirement
sudo apt-get install -y open-iscsi nfs-common
sudo systemctl stop multipathd.service multipathd.socket
sudo systemctl disable multipathd.service multipathd.socket
sudo apt remove multipath-tools -y


sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt-cache madison kubeadm


echo '  '
read -p 'Enter Tools Minor Version: ' MINOR_VERSION
sudo apt-get update
sudo apt-mark unhold kubelet kubeadm kubectl || true
sudo apt-get install -y kubelet=${MINOR_VERSION} kubeadm=${MINOR_VERSION} kubectl=${MINOR_VERSION} --allow-downgrades
sudo apt-mark hold kubelet kubeadm kubectl


# Kubeadm Init
sudo kubeadm init --config ${home_dir}/files/kubeadm/kubeadm-config.yaml

controlplane_name=$(sudo kubectl get nodes --selector='node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' --kubeconfig /etc/kubernetes/admin.conf)

# Untaint ControlPlane
sudo kubectl taint node $controlplane_name node-role.kubernetes.io/control-plane:NoSchedule- --kubeconfig=/etc/kubernetes/admin.conf || exit 0

# Remove LoadBalancer label
sudo kubectl label nodes $controlplane_name node.kubernetes.io/exclude-from-external-load-balancers- --kubeconfig=/etc/kubernetes/admin.conf || exit 0

# Networking and network policy
sudo kubectl create -f ${home_dir}/files/calico/tigera-operator-v${calico_version}.yaml \
  --kubeconfig /etc/kubernetes/admin.conf
sleep 10
sudo kubectl create -f ${home_dir}/files/calico/custom-resources-v${calico_version}.yaml \
  --kubeconfig /etc/kubernetes/admin.conf

# Waiting for Control Plane
echo '  '
echo "⏳ Waiting for Control Plane to be ready..."
sudo kubectl wait --for=condition=Ready -n kube-system pod \
  --selector k8s-app=kube-dns \
  --timeout=360s \
  --kubeconfig=/etc/kubernetes/admin.conf
sudo kubectl wait --for=condition=Ready -n kube-system pod \
  --selector component=etcd \
  --timeout=360s \
  --kubeconfig=/etc/kubernetes/admin.conf
sudo kubectl wait --for=condition=Ready -n kube-system pod \
  --selector component=kube-apiserver \
  --timeout=360s \
  --kubeconfig=/etc/kubernetes/admin.conf
sudo kubectl wait --for=condition=Ready -n kube-system pod \
  --selector component=kube-controller-manager \
  --timeout=360s \
  --kubeconfig=/etc/kubernetes/admin.conf
sudo kubectl wait --for=condition=Ready -n kube-system pod \
  --selector k8s-app=kube-proxy \
  --timeout=360s \
  --kubeconfig=/etc/kubernetes/admin.conf
sudo kubectl wait --for=condition=Ready -n kube-system pod \
  --selector component=kube-scheduler \
  --timeout=360s \
  --kubeconfig=/etc/kubernetes/admin.conf
echo "✅ Conrol Plane is ready."

sudo kubectl create ns flux-system --kubeconfig=/etc/kubernetes/admin.conf

cat "$home_dir/age.agekey" |
sudo kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin \
  --kubeconfig=/etc/kubernetes/admin.conf

echo '  '
sudo flux bootstrap github \
  --token-auth \
  --owner=${git_user} \
  --repository=${git_repo} \
  --branch=main \
  --path=clusters/development \
  --personal --private=false \
  --components-extra=image-reflector-controller,image-automation-controller \
  --kubeconfig=/etc/kubernetes/admin.conf

mkdir -p .kube
sudo cp /etc/kubernetes/admin.conf .kube/config
sudo chown $USER:$USER .kube/config


# Install K9S
curl -LO https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz
tar -xvf k9s_Linux_amd64.tar.gz
rm -rf k9s_Linux_amd64.tar.gz LICENSE README.md
sudo mv k9s /usr/local/bin/
curl -sSfL   https://github.com/cloudnative-pg/cloudnative-pg/raw/main/hack/install-cnpg-plugin.sh |   sudo sh -s -- -b /usr/local/bin

