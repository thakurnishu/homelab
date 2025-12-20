#!/usr/bin/env bash
# ==============================================================================
# Kubernetes Master Node Startup Script
# ==============================================================================
# Description: Configures and initializes a Kubernetes master/control plane node
# Usage: Called automatically by setup-cluster.sh
# ==============================================================================

set -e
source k8s-env
set +a

# ==============================================================================
# COLOR DEFINITIONS
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color
# ==============================================================================
# Helper FUNCTIONS
# ==============================================================================
main_banner() {
  echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${MAGENTA}${BOLD}  $1${NC}"
  echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

end_banner() {
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}${BOLD}    $1${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

header_banner() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}${BOLD}  $1${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

red_alert()     { echo -e "${RED}$1${NC}"; }
yellow_alert()  { echo -e "${YELLOW}$1${NC}"; }
blue_alert()    { echo -e "${BLUE}$1${NC}"; }
success_message(){ echo -e "${GREEN}$1${NC}"; }


# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

wait_for_apt() {
  yellow_alert "  ⏳ Waiting for other apt/dpkg processes to finish..."
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
     || fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
     || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    yellow_alert "     ⌛ Another package manager is running. Waiting 5s..."
    sleep 5
  done
  success_message "  ✓ Package manager available"
}

# ==============================================================================
# CONFIGURATION VALIDATION
# ==============================================================================

REQUIRED_VARS=(
  CONTAINERD_VERSION
  CNI_VERSION
  KUBE_MINOR_VERSION
  KUBE_VERSION
  MASTER_NODE_INTERNAL_IP
  POD_NETWORK_CIDR
  RUNC_VERSION
  SERVICE_NETWORK_CIDR
  CALICO_VERSION
  MASTER_NODE_NAME
  CALICO_ENCAPSULATION_TYPE
)
ARCH=$(dpkg --print-architecture)

# ==============================================================================
# MAIN BANNER
# ==============================================================================
main_banner "Kubernetes Master Node Configuration"
# ==============================================================================
# CONFIGURATION VALIDATION
# ==============================================================================
header_banner "Validating Environment Variables"

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    red_alert "❌ ERROR: Required environment variable '$var' is NOT set or empty."
    exit 1
  fi
  success_message "  ✓ $var = ${!var}"
done


blue_alert "  ℹ️  Architecture: ${ARCH}"
echo ""

if ! which yq >/dev/null 2>&1; then
  blue_alert "  → Installing yq..."
  wget -qO /usr/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}
  chmod +x /usr/bin/yq
  success_message "  ✓ yq installed: $(yq --version)"
else
  success_message "  ✓ yq already installed: $(yq --version)"
fi

echo ""


# ==============================================================================
# HOSTNAME CONFIGURATION
# ==============================================================================
header_banner "Configuring Hostname"

HOSTNAME_ENTRY="127.0.0.1 ${MASTER_NODE_NAME}"
if ! grep -qFx "$HOSTNAME_ENTRY" /etc/hosts; then
  blue_alert "  → Adding hostname entry to /etc/hosts"
  echo "$HOSTNAME_ENTRY" | sudo tee -a /etc/hosts >/dev/null
fi

blue_alert "  → Setting hostname to ${MASTER_NODE_NAME}"
hostnamectl hostname "${MASTER_NODE_NAME}"
success_message "  ✓ Hostname configured"
echo ""

# ==============================================================================
# TERMINAL SETUP
# ==============================================================================
header_banner "Setting Up Terminal Environment"

blue_alert "  → Configuring vim"
cat <<EOF >> ~/.vimrc
colorscheme ron
set tabstop=2
set shiftwidth=2
set expandtab
EOF

blue_alert "  → Configuring bash aliases and completions"
cat <<EOF >> ~/.bashrc
source <(kubectl completion bash)
alias k=kubectl
alias c=clear
complete -F __start_kubectl k
force_color_prompt=yes
EOF

success_message "  ✓ Terminal environment configured"
echo ""

# ==============================================================================
# SYSTEM CONFIGURATION
# ==============================================================================
header_banner "Configuring System Settings"

blue_alert "  → Disabling swap"
swapoff -a
sed -i '/\sswap\s/ s/^\(.*\)$/#\1/g' /etc/fstab

blue_alert "  → Loading kernel modules"
modprobe br_netfilter

blue_alert "  → Configuring network settings"
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system >/dev/null
success_message "  ✓ System settings configured"
echo ""

# ==============================================================================
# CONTAINERD INSTALLATION
# ==============================================================================
header_banner "Installing Containerd v${CONTAINERD_VERSION}"

blue_alert "  ⬇ Downloading containerd from GitHub"
sudo wget -q --show-progress -O /tmp/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz \
  https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz
blue_alert "  → Extracting containerd"
sudo tar Cxzf /usr/local /tmp/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz

blue_alert "  → Configuring containerd service"
sudo mkdir -p /usr/local/lib/systemd/system /etc/containerd

sudo wget -q --show-progress -O /usr/local/lib/systemd/system/containerd.service \
  https://raw.githubusercontent.com/thakurnishu/homelab/refs/heads/proxmox/homelab-setup/kubeadm/containerd/containerd.service
sudo wget -q --show-progress -O /etc/containerd/config.toml \
  https://raw.githubusercontent.com/thakurnishu/homelab/refs/heads/proxmox/homelab-setup/kubeadm/containerd/config.toml

blue_alert "  → Starting containerd service"
sudo systemctl daemon-reload
sudo systemctl enable --now containerd >/dev/null 2>&1
sudo systemctl restart containerd

success_message "  ✓ Containerd installed and running"
echo ""

# ==============================================================================
# RUNC INSTALLATION
# ==============================================================================
header_banner "Installing Runc v${RUNC_VERSION}"

blue_alert "  ⬇ Downloading runc from GitHub"
sudo wget -q --show-progress -O /tmp/runc-${RUNC_VERSION}.${ARCH} \
  https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH}
blue_alert "  → Installing runc"
sudo install -m 755 /tmp/runc-${RUNC_VERSION}.${ARCH} /usr/local/sbin/runc

success_message "  ✓ Runc installed"
echo ""

# ==============================================================================
# CNI PLUGINS INSTALLATION
# ==============================================================================
header_banner "Installing CNI Plugins v${CNI_VERSION}"

sudo mkdir -p /opt/cni/bin

blue_alert "  ⬇ Downloading CNI plugins from GitHub"
sudo wget -q --show-progress -O /tmp/cni-plugins-linux-${ARCH}-v${CNI_VERSION}.tgz \
  https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/cni-plugins-linux-${ARCH}-v${CNI_VERSION}.tgz
blue_alert "  → Extracting CNI plugins"
sudo tar Cxzf /opt/cni/bin /tmp/cni-plugins-linux-${ARCH}-v${CNI_VERSION}.tgz

success_message "  ✓ CNI plugins installed"
echo ""

# ==============================================================================
# KUBERNETES PACKAGES INSTALLATION
# ==============================================================================
header_banner "Installing Kubernetes v${KUBE_VERSION}"

blue_alert "  → Configuring Kubernetes APT repository"
mkdir -p /etc/apt/keyrings
rm /etc/apt/keyrings/kubernetes-${KUBE_MINOR_VERSION}-apt-keyring.gpg 2>/dev/null || true
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_MINOR_VERSION}/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-${KUBE_MINOR_VERSION}-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-${KUBE_MINOR_VERSION}-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_MINOR_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

blue_alert "  → Installing packages from APT repository"
wait_for_apt
apt update >/dev/null 2>&1
wait_for_apt
apt install -y \
  bash-completion binutils apt-transport-https ca-certificates curl gpg \
  kubelet=${KUBE_VERSION}-1.1 kubeadm=${KUBE_VERSION}-1.1 kubectl=${KUBE_VERSION}-1.1 \
  >/dev/null 2>&1

blue_alert "  → Marking packages to prevent auto-upgrade"
apt-mark hold kubelet kubeadm kubectl >/dev/null 2>&1

success_message "  ✓ Kubernetes packages installed"
echo ""

# ==============================================================================
# KUBELET CONFIGURATION
# ==============================================================================
header_banner "Configuring Kubelet"

blue_alert "  → Setting node IP to ${MASTER_NODE_INTERNAL_IP}"

KUBELET_ENV_FILE="/etc/default/kubelet"
EXISTING_ARGS=$(sudo grep "^KUBELET_EXTRA_ARGS=" "$KUBELET_ENV_FILE" 2>/dev/null | sed 's/^KUBELET_EXTRA_ARGS=//g' | tr -d '"')

if [[ -z "$EXISTING_ARGS" ]]; then
  NEW_ARGS="--node-ip=${MASTER_NODE_INTERNAL_IP}"
elif echo "$EXISTING_ARGS" | grep -q -- "--node-ip="; then
  NEW_ARGS=$(echo "$EXISTING_ARGS" | sed "s/--node-ip=[^ ]*/--node-ip=${MASTER_NODE_INTERNAL_IP}/g")
else
  NEW_ARGS="$EXISTING_ARGS --node-ip=${MASTER_NODE_INTERNAL_IP}"
fi

if sudo grep -q "^KUBELET_EXTRA_ARGS=" "$KUBELET_ENV_FILE" 2>/dev/null; then
  sudo sed -i "s|^KUBELET_EXTRA_ARGS=.*|KUBELET_EXTRA_ARGS=\"${NEW_ARGS}\"|g" "$KUBELET_ENV_FILE"
else
  echo "KUBELET_EXTRA_ARGS=\"${NEW_ARGS}\"" | sudo tee -a "$KUBELET_ENV_FILE" >/dev/null
fi
success_message "  ✓ Kubelet configured"
echo ""

# ==============================================================================
# APPARMOR
# ==============================================================================
header_banner "Disabling AppArmor"

blue_alert "  → Stopping AppArmor service"
aa-teardown >/dev/null 2>&1 || true
service apparmor stop >/dev/null 2>&1 || true
systemctl disable apparmor >/dev/null 2>&1 || true

wait_for_apt
blue_alert "  → Removing AppArmor package"
apt-get remove -y apparmor >/dev/null 2>&1 || true

success_message "  ✓ AppArmor disabled"
echo ""

# ==============================================================================
# SERVICE STARTUP
# ==============================================================================
header_banner "Starting Services"

blue_alert "  → Reloading systemd daemon"
systemctl daemon-reload

blue_alert "  → Enabling and restarting containerd"
systemctl enable containerd >/dev/null 2>&1
systemctl restart containerd

blue_alert "  → Enabling and starting kubelet"
systemctl enable kubelet >/dev/null 2>&1
systemctl start kubelet

success_message "  ✓ All services started"
echo ""

# ==============================================================================
# KUBERNETES CLUSTER INITIALIZATION
# ==============================================================================
header_banner "Initializing Kubernetes Cluster"

blue_alert "  → Removing previous kubeconfig (if exists)"
rm /root/.kube/config 2>/dev/null || true

yellow_alert "  ⚙️  Running kubeadm init..."
blue_alert "     • Kubernetes Version: ${KUBE_VERSION}"
blue_alert "     • Control Plane: ${MASTER_NODE_INTERNAL_IP}"
blue_alert "     • Pod Network CIDR: ${POD_NETWORK_CIDR}"
blue_alert "     • Service CIDR: ${SERVICE_NETWORK_CIDR}"
echo ""

kubeadm init --kubernetes-version=${KUBE_VERSION} \
  --ignore-preflight-errors=NumCPU \
  --skip-token-print \
  --node-name=${MASTER_NODE_NAME} \
  --control-plane-endpoint=${MASTER_NODE_INTERNAL_IP} \
  --apiserver-advertise-address=${MASTER_NODE_INTERNAL_IP} \
  --apiserver-cert-extra-sans=${MASTER_NODE_INTERNAL_IP} \
  --pod-network-cidr ${POD_NETWORK_CIDR} \
  --service-cidr ${SERVICE_NETWORK_CIDR}

blue_alert "  → Configuring kubectl access"
mkdir -p ~/.kube
sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config

success_message "  ✓ Cluster initialized"
echo ""

# ==============================================================================
# CONTROL PLANE VERIFICATION
# ==============================================================================
header_banner "Waiting for Control Plane Components"

yellow_alert "  ⏳ This may take a few minutes..."
echo ""
sleep 20

blue_alert "  → Waiting for etcd..."
kubectl wait --for=condition=Ready -n kube-system pod --selector component=etcd --timeout=360s

blue_alert "  → Waiting for kube-apiserver..."
kubectl wait --for=condition=Ready -n kube-system pod --selector component=kube-apiserver --timeout=360s

blue_alert "  → Waiting for kube-controller-manager..."
kubectl wait --for=condition=Ready -n kube-system pod --selector component=kube-controller-manager --timeout=360s

blue_alert "  → Waiting for kube-proxy..."
kubectl wait --for=condition=Ready -n kube-system pod --selector k8s-app=kube-proxy --timeout=360s

blue_alert "  → Waiting for kube-scheduler..."
kubectl wait --for=condition=Ready -n kube-system pod --selector component=kube-scheduler --timeout=360s

success_message "  ✓ Control Plane is ready"
echo ""

# TODO:
# echo "  1. Deploy CNI network plugin (Flannel / Calico)"
blue_alert "  → Installing Calico operator CRDs"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/operator-crds.yaml >/dev/null 2>&1

blue_alert "  → Installing Tigera operator"
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/tigera-operator.yaml >/dev/null 2>&1

blue_alert "  → Configuring custom resources"
blue_alert "     • Pod CIDR: ${POD_NETWORK_CIDR}"

wget -q --show-progress -O calico-custom-resources-${CALICO_VERSION}.yaml \
  https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/custom-resources.yaml

# Pod Cidr
yq -i "(. | select(.kind == \"Installation\") | .spec.calicoNetwork.ipPools[0].cidr) = \"${POD_NETWORK_CIDR}\"" \
  calico-custom-resources-${CALICO_VERSION}.yaml

# EncapsulationType
yq -i "(. | select(.kind == \"Installation\") | .spec.calicoNetwork.ipPools[0].encapsulation) = \"${CALICO_ENCAPSULATION_TYPE}\"" \
  calico-custom-resources-${CALICO_VERSION}.yaml

blue_alert "  → Applying custom resources"
until kubectl create -f calico-custom-resources-${CALICO_VERSION}.yaml >/dev/null 2>&1; do
  yellow_alert "     ⌛ Calico apply failed, retrying in 10 seconds..."
  sleep 10
done

header_banner "Waiting for DNS Services"
yellow_alert "  ⏳ Waiting for KubeDNS to be ready..."
kubectl wait --for=condition=Ready -n kube-system pod \
  --selector k8s-app=kube-dns --timeout=360s
success_message "  ✓ KubeDNS is ready"
echo ""

yellow_alert "  Run below in worker nodes to join cluster: "
blue_alert "→ sudo $(sudo kubeadm token create --print-join-command --ttl 0)"
end_banner "✓ MASTER NODE CONFIGURATION COMPLETE"
