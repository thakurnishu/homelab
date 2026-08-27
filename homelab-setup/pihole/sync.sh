#!/bin/bash
# Pull live Pi-hole config out of the container back into this directory, so
# changes made through the web UI end up in git.
#
#   bash homelab-setup/pihole/sync.sh
#   git diff homelab-setup/pihole/
#
# Writes: pihole.toml (pwhash redacted), adlists.txt, custom-dns.list
# Never writes secrets — the password hash is stripped on the way out.

set -euo pipefail

CT_IP="${CT_IP:-192.168.1.111}"
PVE_KEY="${PVE_KEY:-$HOME/.ssh/proxmox}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ct() { ssh -i "$PVE_KEY" "root@${CT_IP}" "$@"; }

if ! ct true 2>/dev/null; then
  echo "ERROR: cannot SSH to root@${CT_IP}" >&2
  exit 1
fi

echo "==> pihole.toml (redacting pwhash, stripping timestamp)"
# pihole-FTL rewrites a "Last updated on <time>" header every time it touches the
# file, which would otherwise show up as a diff on every sync even when no
# setting changed. Normalise it so diffs only carry real config changes.
ct 'sed -e "s|^# Last updated on .*|# Last updated on <stripped by sync.sh for stable diffs>|" \
        -e "s|^\(\s*pwhash = \).*|\1\"\" # REDACTED - set your own: ssh -i ~/.ssh/proxmox root@192.168.1.111 pihole setpassword|" \
    /etc/pihole/pihole.toml' > "${HERE}/pihole.toml"

# Guard: never let a real hash reach the repo, even if the sed above stops
# matching after a Pi-hole upgrade changes the file's formatting.
if grep -qE '^\s*pwhash = "[^"]+"' "${HERE}/pihole.toml"; then
  echo "ERROR: pwhash was not redacted — refusing to leave a secret in the repo." >&2
  rm -f "${HERE}/pihole.toml"
  exit 1
fi

echo "==> adlists.txt"
{
  echo "# Blocklist URLs, one per line. Authoritative — apply-settings.sh will"
  echo "# disable any list on the container that is not present here."
  ct 'sqlite3 /etc/pihole/gravity.db "SELECT address FROM adlist WHERE enabled=1 ORDER BY address;"'
} > "${HERE}/adlists.txt"

echo "==> custom-dns.list"
{
  echo "# Local DNS records, one per line: <IP> <hostname>"
  echo "# e.g. 192.168.1.110 pve.local.nishantlabs.cloud"
  ct 'awk "/^\s+hosts = \[/{f=1;next} f&&/^\s+\]/{exit} f{print}" /etc/pihole/pihole.toml \
      | sed "s/^\s*\"//; s/\",\?\s*$//" | grep -v "^\s*$"' || true
} > "${HERE}/custom-dns.list"

echo
echo "Synced. Review with:  git diff homelab-setup/pihole/"
echo -n "  adlists: ";     grep -cvE '^\s*(#|$)' "${HERE}/adlists.txt"
echo -n "  custom DNS: ";  grep -cvE '^\s*(#|$)' "${HERE}/custom-dns.list"
