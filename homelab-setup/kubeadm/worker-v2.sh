#!/usr/bin/env bash
# ==============================================================================
# Kubernetes Worker Node Startup Script
# ==============================================================================
# Description: Configures and initializes a Kubernetes worker node
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
# MAIN
# ==============================================================================
main_banner "Kubernetes Worker Node Configuration"

# ==============================================================================
# CONFIGURATION VALIDATION
# ==============================================================================
header_banner "Validating Environment Variables"

REQUIRED_VARS=(
  CONTAINERD_VERSION
  CNI_VERSION
  KUBE_MINOR_VERSION
  KUBE_VERSION
  WORKER_NODE_INTERNAL_IP
  RUNC_VERSION
  WORKER_NODE_NAME
)

ARCH=$(dpkg --print-architecture)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    red_alert "❌ ERROR: Required environment variable '$var' is NOT set or empty."
    exit 1
  fi
  success_message "  ✓ $var = ${!var}"
done

blue_alert "  ℹ️  Architecture: ${ARCH}"
echo ""

# ==============================================================================
# HOSTNAME CONFIGURATION
# ==============================================================================
header_banner "Configuring Hostname"

HOSTNAME_ENTRY="127.0.0.1 ${WORKER_NODE_NAME}"
if ! grep -qFx "$HOSTNAME_ENTRY" /etc/hosts; then
  blue_alert "  → Adding hostname entry to /etc/hosts"
  echo "$HOSTNAME_ENTRY" | sudo tee -a /etc/hosts >/dev/null
fi

blue_alert "  → Setting hostname to ${WORKER_NODE_NAME}"
hostnamectl hostname "${WORKER_NODE_NAME}"
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

blue_alert "  ⬇ Downloading containerd"
wget -q --show-progress -O /tmp/containerd.tar.gz \
  https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz
tar Cxzf /usr/local /tmp/containerd.tar.gz

mkdir -p /etc/containerd /usr/local/lib/systemd/system
sudo wget -q --show-progress -O /usr/local/lib/systemd/system/containerd.service \
  https://raw.githubusercontent.com/thakurnishu/homelab/refs/heads/proxmox/homelab-setup/kubeadm/containerd/containerd.service
sudo wget -q --show-progress -O /etc/containerd/config.toml \
  https://raw.githubusercontent.com/thakurnishu/homelab/refs/heads/proxmox/homelab-setup/kubeadm/containerd/config.toml

systemctl daemon-reload
systemctl enable --now containerd > /dev/null 2>&1
success_message "  ✓ Containerd installed and running"
echo ""

# ==============================================================================
# RUNC INSTALLATION
# ==============================================================================
header_banner "Installing Runc v${RUNC_VERSION}"

blue_alert "  ⬇ Downloading runc"
wget -q --show-progress -O /tmp/runc \
  https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH}
install -m 755 /tmp/runc /usr/local/sbin/runc

success_message "  ✓ Runc installed"
echo ""

# ==============================================================================
# CNI INSTALLATION
# ==============================================================================
header_banner "Installing CNI Plugins v${CNI_VERSION}"

mkdir -p /opt/cni/bin

blue_alert "  ⬇ Downloading CNI plugins"
wget -q --show-progress -O /tmp/cni.tgz \
  https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/cni-plugins-linux-${ARCH}-v${CNI_VERSION}.tgz
tar Cxzf /opt/cni/bin /tmp/cni.tgz

success_message "  ✓ CNI plugins installed"
echo ""

# ==============================================================================
# KUBERNETES INSTALLATION
# ==============================================================================
header_banner "Installing Kubernetes v${KUBE_VERSION}"

mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBE_MINOR_VERSION}/deb/Release.key \
 | gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBE_MINOR_VERSION}/deb/ /" \
 | tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

wait_for_apt
apt update >/dev/null 2>&1
apt install -y kubelet=${KUBE_VERSION}-1.1 kubeadm=${KUBE_VERSION}-1.1 kubectl=${KUBE_VERSION}-1.1 >/dev/null 2>&1
apt-mark hold kubelet kubeadm kubectl >/dev/null 2>&1

success_message "  ✓ Kubernetes packages installed"
echo ""

# ==============================================================================
# KUBELET CONFIGURATION
# ==============================================================================
header_banner "Configuring Kubelet"

echo "KUBELET_EXTRA_ARGS=\"--node-ip=${WORKER_NODE_INTERNAL_IP}\"" > /etc/default/kubelet
success_message "  ✓ Kubelet configured"
echo ""

# ==============================================================================
# APPARMOR
# ==============================================================================
header_banner "Disabling AppArmor"

systemctl stop apparmor >/dev/null 2>&1 || true
systemctl disable apparmor >/dev/null 2>&1 || true
wait_for_apt
apt remove -y apparmor >/dev/null 2>&1 || true

success_message "  ✓ AppArmor disabled"
echo ""

# ==============================================================================
# FINAL
# ==============================================================================
end_banner "✓ WORKER NODE CONFIGURATION COMPLETE"

yellow_alert "⚠️  Node is ready to join the cluster using kubeadm join command"
