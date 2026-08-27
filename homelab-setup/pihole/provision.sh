#!/bin/bash
# Create the Pi-hole LXC container on the Proxmox node from nothing.
# Idempotency: refuses to run if the CT already exists — it will not clobber
# a working container. Destroy it deliberately first if you mean to rebuild.
#
#   bash homelab-setup/pihole/provision.sh
#
# Afterwards run apply-settings.sh to push tracked settings and adlists.

set -euo pipefail

PVE_HOST="${PVE_HOST:-192.168.1.110}"
PVE_KEY="${PVE_KEY:-$HOME/.ssh/proxmox}"
CTID="${CTID:-100}"
HOSTNAME="pihole"
CT_IP="192.168.1.111"
CT_CIDR="24"
CT_GW="192.168.1.1"
CT_MAC="58:11:22:7F:D6:AF"     # fixed: a router DHCP reservation may rely on it
STORAGE="local-lvm"            # thin LVM — dir storage cannot snapshot a CT
DISK_GB=8
MEMORY_MB=512
SWAP_MB=512
CORES=1
TEMPLATE="local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
SSH_PUBKEY="${SSH_PUBKEY:-$HOME/.ssh/proxmox.pub}"

pve() { ssh -i "$PVE_KEY" "root@${PVE_HOST}" "$@"; }

echo "==> Checking node"
if ! pve true 2>/dev/null; then
  echo "ERROR: cannot SSH to root@${PVE_HOST} with key ${PVE_KEY}" >&2
  exit 1
fi

# Without quorum /etc/pve is read-only and every write fails with a confusing
# "Permission denied" that never mentions quorum. Check before doing anything.
if pve 'pvecm status 2>/dev/null | grep -q "Activity blocked"'; then
  echo "ERROR: cluster has no quorum — /etc/pve is read-only." >&2
  echo "  The second node is probably powered off. If so, run:" >&2
  echo "    ssh proxmox 'pvecm expected 1'" >&2
  echo "  Do NOT do this if the other node is running but unreachable (split-brain)." >&2
  exit 1
fi

echo "==> Checking CTID ${CTID} is free"
if pve "pct status ${CTID}" >/dev/null 2>&1; then
  echo "ERROR: CT ${CTID} already exists. Refusing to overwrite." >&2
  echo "  To rebuild deliberately:" >&2
  echo "    ssh proxmox 'pct stop ${CTID}; pct destroy ${CTID} --purge'" >&2
  exit 1
fi

echo "==> Checking ${CT_IP} is free"
if ping -c1 -W 1 "${CT_IP}" >/dev/null 2>&1; then
  echo "ERROR: ${CT_IP} already answers ping — something else is using it." >&2
  exit 1
fi

echo "==> Ensuring Debian template is present"
if ! pve "pveam list local | grep -q debian-12-standard"; then
  pve "pveam update && pveam download local debian-12-standard_12.12-1_amd64.tar.zst"
fi

echo "==> Copying SSH public key to node"
scp -i "$PVE_KEY" -q "$SSH_PUBKEY" "root@${PVE_HOST}:/root/pihole_key.pub"

echo "==> Creating CT ${CTID}"
pve "pct create ${CTID} ${TEMPLATE} \
  --hostname ${HOSTNAME} --memory ${MEMORY_MB} --swap ${SWAP_MB} --cores ${CORES} \
  --rootfs ${STORAGE}:${DISK_GB} \
  --net0 name=eth0,bridge=vmbr0,hwaddr=${CT_MAC},ip=${CT_IP}/${CT_CIDR},gw=${CT_GW} \
  --nameserver 1.1.1.1 --unprivileged 1 --features nesting=1 \
  --ssh-public-keys /root/pihole_key.pub --onboot 1 \
  --description 'Pi-hole DNS/DHCP - managed from homelab/homelab-setup/pihole'"

pve "pct start ${CTID}"
echo "==> Waiting for container network"
for _ in $(seq 1 30); do
  ping -c1 -W 1 "${CT_IP}" >/dev/null 2>&1 && break
  sleep 2
done

echo "==> Installing prerequisites"
ct() { ssh -i "$PVE_KEY" -o StrictHostKeyChecking=accept-new "root@${CT_IP}" "$@"; }
ct 'export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq curl ca-certificates procps sqlite3 >/dev/null'

echo "==> Seeding install answers"
ct "mkdir -p /etc/pihole && cat > /etc/pihole/setupVars.conf <<'EOF'
PIHOLE_INTERFACE=eth0
IPV4_ADDRESS=${CT_IP}/${CT_CIDR}
IPV6_ADDRESS=
PIHOLE_DNS_1=1.1.1.1
PIHOLE_DNS_2=1.0.0.1
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
CACHE_SIZE=10000
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
DNSMASQ_LISTENING=local
BLOCKING_ENABLED=true
WEBPASSWORD=
EOF"

echo "==> Installing Pi-hole"
# Downloaded to a file rather than piped into a shell, so it can be inspected.
ct 'curl -sSL -o /root/pihole-install.sh https://install.pi-hole.net
    echo "installer sha256: $(sha256sum /root/pihole-install.sh | cut -d" " -f1)"
    bash /root/pihole-install.sh --unattended'

echo "==> Verifying"
ct 'systemctl is-active pihole-FTL'
echo -n "  resolves github.com: "; ct 'dig +short +time=3 github.com @127.0.0.1 | head -1'
echo -n "  dhcp.active: "; ct 'awk "/^\[dhcp\]/{f=1} f&&/^  active/{print \$3; exit}" /etc/pihole/pihole.toml'

cat <<EOF

Done. CT ${CTID} is running at http://${CT_IP}/admin

Next:
  1. bash homelab-setup/pihole/apply-settings.sh
  2. Set an admin password:
       ssh pihole 'pihole setpassword'
  3. DHCP is OFF. See README before enabling it.
EOF
