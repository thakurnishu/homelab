# Pi-hole — LXC container on Proxmox

Network-wide DNS ad blocking, running as an unprivileged LXC container on the
Proxmox node `pve`. Intended to eventually also serve DHCP, replacing the ISP
router's DHCP server.

This directory is the tracked source of truth. The container itself is
disposable — `provision.sh` rebuilds it from scratch.

## Current deployment

| | |
|---|---|
| Proxmox node | `pve` — `192.168.1.110` |
| CTID | `100` |
| Hostname | `pihole` |
| IP | `192.168.1.111/24`, gw `192.168.1.1` |
| MAC | `58:11:22:7F:D6:AF` (fixed — a router DHCP reservation may depend on it) |
| Resources | 1 core · 512 MB RAM · 512 MB swap · 8 GB rootfs |
| Storage | `local-lvm` (thin LVM — supports snapshots; dir storage does not) |
| Base | `debian-12-standard` |
| Privileged | **No** — unprivileged |
| Start on boot | Yes (`onboot: 1`) |
| Pi-hole | Core v6.4.3 · Web v6.6 · FTL v6.7 |
| **DHCP** | **Disabled** — the router at `192.168.1.1` is still the DHCP server |

Admin UI: <http://192.168.1.111/admin>

## Files

| File | Purpose |
|---|---|
| `provision.sh` | Creates the CT and installs Pi-hole from nothing |
| `apply-settings.sh` | Applies tracked settings + adlists to a running CT |
| `sync.sh` | Pulls live config out of the CT back into this directory |
| `pihole.toml` | Full config snapshot. `pwhash` is **redacted** — reference/restore only |
| `adlists.txt` | Blocklist URLs, one per line — authoritative |
| `custom-dns.list` | Local DNS records (`IP hostname`) — authoritative |
| `pihole-admin-password.secret.sops.yaml` | Admin password, sops-encrypted — **not created yet**, optional (see below) |

## Admin password

The password is **not** stored here. `provision.sh` does not set one — the
installer runs with an empty `WEBPASSWORD`, so set your own before first login:

```bash
ssh -i ~/.ssh/proxmox root@192.168.1.111 'pihole setpassword'
```

It prompts twice, then log in at <http://192.168.1.111/admin>. There is no email
recovery — the CLI is the only reset path.

> On the container built 2026-08-27 a random password was set manually and left
> at `/root/.pihole_pw`. Read it once if needed, then remove it:
> `ssh -i ~/.ssh/proxmox root@192.168.1.111 'shred -u /root/.pihole_pw'`

Tracking the password in git is **optional**. To do it, follow the repo's
existing sops convention — write the plaintext to
`pihole-admin-password.secret.yaml` (gitignored by `*.secret.yaml`), then:

```bash
bash scripts/sops-encrypt-all.sh
```

That produces `pihole-admin-password.secret.sops.yaml`, which **is** committed.
Delete the plaintext afterwards. The file uses Kubernetes `Secret` shape purely
so the repo's existing `.sops.yaml` rules (`encrypted_regex: ^(data|stringData)$`)
apply unchanged — it is not deployed to the cluster.

## Rebuilding from scratch

```bash
bash homelab-setup/pihole/provision.sh
bash homelab-setup/pihole/apply-settings.sh
```

`provision.sh` refuses to run if CTID 100 already exists, so it will not silently
destroy a working container.

## Saving changes made in the web UI

Changes made through the Pi-hole admin UI live only on the container. Pull them
back into git:

```bash
bash homelab-setup/pihole/sync.sh
git diff homelab-setup/pihole/
```

## Enabling DHCP later — read first

DHCP is deliberately off. Turning it on is the one step that changes your
network, so it is not automated here.

1. **Disable DHCP on the router** at `192.168.1.1` (LAN → DHCP Server) **first**.
   Two DHCP servers on one L2 segment is not a redundancy setup — clients accept
   whichever reply arrives first, producing nondeterministic addressing that
   looks like random network failure.
2. Then enable it in Pi-hole (Settings → DHCP), with a range that **excludes**
   `192.168.1.111` and the Proxmox node `192.168.1.110`.
3. Re-run `sync.sh` to capture the new config.

Once Pi-hole serves DHCP, it becomes a hard dependency of the whole network: if
CT 100 is down, nothing new gets an address. `onboot: 1` is already set for this
reason. Existing devices keep their leases until expiry, so an outage degrades
gradually rather than instantly.

**Do not move DHCP into the Kubernetes cluster.** Pi-hole serving addresses to
the machines that run the cluster that runs Pi-hole cannot cold-start. The
disabled k8s manifests in `infrastructure/configs/pihole/` are fine for DNS only.

### Testing DHCP without disrupting the LAN

Bind to loopback so nothing on the network can receive a lease:

```bash
timeout 4 dnsmasq -d --port=0 --interface=lo --bind-interfaces \
  --dhcp-range=10.99.99.10,10.99.99.20,1h
```

Verified: an **unprivileged** CT on PVE 9 retains `cap_net_admin`, `cap_net_raw`,
and `cap_net_bind_service`, and `dnsmasq` starts its DHCP engine successfully.
Older guides claiming Pi-hole DHCP needs a privileged container are out of date.

## Related

- Container lifecycle operations: `.claude/skills/proxmox-ct/SKILL.md`
- VM operations: `.claude/skills/proxmox-vm/SKILL.md`
- Disabled in-cluster Pi-hole: `infrastructure/configs/pihole/`
