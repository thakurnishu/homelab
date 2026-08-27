#!/bin/bash
# Push tracked settings from this directory to the running Pi-hole container.
# This directory is authoritative: adlists.txt and custom-dns.list here overwrite
# whatever is on the container.
#
#   bash homelab-setup/pihole/apply-settings.sh
#
# Settings are applied with `pihole-FTL --config`, which writes pihole.toml
# safely, rather than copying the tracked pihole.toml over the live one — that
# snapshot is for reference and disaster recovery, and its schema shifts between
# Pi-hole versions.

set -euo pipefail

CT_IP="${CT_IP:-192.168.1.111}"
PVE_KEY="${PVE_KEY:-$HOME/.ssh/proxmox}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ct() { ssh -i "$PVE_KEY" "root@${CT_IP}" "$@"; }

if ! ct true 2>/dev/null; then
  echo "ERROR: cannot SSH to root@${CT_IP}" >&2
  exit 1
fi

echo "==> Applying settings"
# Non-default settings. Everything else is left at Pi-hole's defaults so this
# stays readable and survives version upgrades.
ct 'pihole-FTL --config dns.domainNeeded true'    >/dev/null
ct 'pihole-FTL --config dns.expandHosts true'     >/dev/null
ct 'pihole-FTL --config dns.interface eth0'       >/dev/null
ct 'pihole-FTL --config dns.cache.size 10000'     >/dev/null

echo "==> Syncing adlists"
if [[ -s "${HERE}/adlists.txt" ]]; then
  # Enable/insert the tracked lists, then disable any that are no longer tracked.
  # The unique constraint is composite — UNIQUE(address, type) — so the upsert
  # must name both columns. type 0 = blocklist, 1 = allowlist; only blocklists
  # are tracked here.
  while IFS= read -r url; do
    [[ -z "$url" || "$url" =~ ^# ]] && continue
    ct "sqlite3 /etc/pihole/gravity.db \
      \"INSERT INTO adlist (address, enabled, type) VALUES ('${url}', 1, 0)
        ON CONFLICT(address, type) DO UPDATE SET enabled=1;\"" >/dev/null
    echo "    + ${url}"
  done < "${HERE}/adlists.txt"

  TRACKED=$(grep -vE '^\s*(#|$)' "${HERE}/adlists.txt" | sed "s/'/''/g; s/.*/'&'/" | paste -sd, -)
  if [[ -n "$TRACKED" ]]; then
    ct "sqlite3 /etc/pihole/gravity.db \
      \"UPDATE adlist SET enabled=0 WHERE type=0 AND address NOT IN (${TRACKED});\"" >/dev/null
  fi
fi

echo "==> Syncing custom DNS records"
# Custom DNS lives in pihole.toml under dns.hosts in v6, not in a hosts file.
if [[ -s "${HERE}/custom-dns.list" ]]; then
  ENTRIES=$(grep -vE '^\s*(#|$)' "${HERE}/custom-dns.list" | sed 's/^/"/; s/$/"/' | paste -sd, - || true)
  if [[ -n "$ENTRIES" ]]; then
    ct "pihole-FTL --config dns.hosts '[${ENTRIES}]'" >/dev/null
    echo "    applied: $(grep -cvE '^\s*(#|$)' "${HERE}/custom-dns.list") record(s)"
  else
    ct "pihole-FTL --config dns.hosts '[]'" >/dev/null
    echo "    (none tracked — cleared)"
  fi
fi

echo "==> Rebuilding gravity (downloads blocklists)"
ct 'pihole -g' 2>&1 | tail -4

echo "==> Restarting DNS"
ct 'pihole restartdns' >/dev/null
sleep 2

echo "==> Verifying"
ct 'systemctl is-active pihole-FTL'
echo -n "  resolves github.com: "; ct 'dig +short +time=3 github.com @127.0.0.1 | head -1'
echo -n "  dhcp.active: "; ct 'awk "/^\[dhcp\]/{f=1} f&&/^  active/{print \$3; exit}" /etc/pihole/pihole.toml'
echo "Done."
