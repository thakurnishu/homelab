---
name: proxmox-ct
description: Manage LXC containers (CTs) on the homelab Proxmox node — list, create, update, and delete. Use whenever the user asks to create / run / manage a container, LXC, or CT on Proxmox, or names a lightweight service to host (Pi-hole, DNS, DHCP, reverse proxy, monitoring agent). Also triggers on "pct", "lxc", "container on pve". For full virtual machines use the proxmox-vm skill instead.
---

# Proxmox LXC container management

Manage LXC containers on the homelab Proxmox node over SSH. Containers use `pct`; VMs use `qm` and live in the **proxmox-vm** skill.

## VM or container?

| Use a **CT** when | Use a **VM** when |
|---|---|
| Linux service appliance — Pi-hole, DNS, reverse proxy, monitoring | Non-Linux OS, or a specific kernel needed |
| RAM matters (a CT idles at ~50–130 MB) | Kubernetes node — kubelet on LXC is painful |
| Fast boot wanted (~1 s vs ~15 s) | Docker-in-guest as the primary workload |
| Shared host kernel is fine | Hard isolation required |

CTs share the host kernel — that's the whole efficiency win and the whole security caveat.

## Connection

```bash
ssh proxmox '<command>'      # the node
ssh pihole  '<command>'      # CT 100, directly
```

These are aliases in `~/.ssh/config`, all using the same key:

```
Host proxmox pve
  HostName 192.168.1.110
  User root
  Port 22
  IdentityFile ~/.ssh/proxmox

Host pihole
  HostName 192.168.1.111
  User root
  Port 22
  IdentityFile ~/.ssh/proxmox
```

If an alias is missing, the explicit form is equivalent: `ssh -i ~/.ssh/proxmox root@<ip>`. **Scripts should keep the explicit form** so they work on machines without the aliases.

Containers are also reachable without any key at all via `pct exec <ctid> -- <command>` from the node — useful when SSH isn't set up yet or has broken.

### Keep `~/.ssh/config` in sync — part of every create and delete

Creating or destroying a CT is not finished until `~/.ssh/config` matches reality. Stale entries are worse than missing ones: `ssh oldct` hangs on a dead address, and once an IP is recycled it silently points at a different machine.

**Always back up first** — this file is not in git:

```bash
cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d-%H%M%S)
```

**After creating** a CT that will stick around, once it's verified reachable:

```bash
cat >> ~/.ssh/config <<'EOF'

# CT <ctid> — created <date>
Host <name>
  HostName 192.168.1.<X>
  User root
  Port 22
  IdentityFile ~/.ssh/proxmox
EOF
ssh -o BatchMode=yes -o ConnectTimeout=8 <name> 'hostname'   # confirm
```

Skip it for throwaway or test containers — only add entries for things that outlive the session.

**After destroying** a CT, remove its entry and its host key:

```bash
# 1. drop the Host block (check by eye before and after — do not blind-delete)
python3 - <<'PY'
import re, pathlib
p = pathlib.Path.home() / ".ssh/config"
s = p.read_text()
s2 = re.sub(r"(?m)^(?:#[^\n]*\n)?Host <name>\n(?:[ \t]+[^\n]*\n)*", "", s)
p.write_text(s2)
print("removed" if s2 != s else "no matching entry found")
PY

# 2. clear the host key — a recycled IP otherwise triggers a mismatch warning
ssh-keygen -R 192.168.1.<X>
```

The pattern matches a single-name `Host` line. An entry declaring synonyms (`Host proxmox pve`) will report *no matching entry found* — edit those by hand.

`ssh-keygen -R` matters here in particular: CTs are cheap to create and destroy, so addresses get recycled far more often than with VMs. Skipping it produces `REMOTE HOST IDENTIFICATION HAS CHANGED` later, which reads like an attack rather than a reused address.

**When changing a CT's IP**, update `HostName` and run `ssh-keygen -R` on the *old* address.

**Bash sandbox:** the node is on the LAN and the default Bash sandbox blocks outbound network. Every `ssh` call needs `dangerouslyDisableSandbox: true`, or it fails with a misleading connection error.

## Node facts (verified)

| Item | Value |
|---|---|
| Node / IP | `pve` / `192.168.1.110` |
| Version | Proxmox VE 9.0.3 |
| Resources | 4 cores, 15.9 GB RAM |
| Bridge | `vmbr0` → `192.168.1.0/24`, gw `192.168.1.1` |
| CT template | `local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst` |

### Storage — the default differs from the VM skill

| Storage | CT rootfs | Snapshots |
|---|---|---|
| **`local-lvm`** (lvmthin) | **default for CTs** | **yes** — verified working |
| `pve-harddisk-filesystem` (dir) | works, 480 GB | **no** — `snapshot feature is not available` |
| `local` (dir) | templates only, no `rootdir` | — |
| `pve-worker-01-lvm-thin` | other node — never use | — |

A CT rootfs on dir storage is a `.raw` file, and Proxmox cannot snapshot it. `local-lvm` gives thin-provisioned snapshot and rollback, both verified. **Default CTs to `local-lvm`** unless the container needs more than ~148 GB, in which case use the dir storage and accept no snapshots.

### Quorum caveat — check this first when writes fail

Two-node cluster, second node usually powered off. Without quorum `/etc/pve` remounts read-only and every write fails with a confusing `Permission denied` that never mentions quorum.

```bash
ssh proxmox 'pvecm status | grep -E "Total votes|Quorum:|Activity"'
# If "Activity blocked" appears:
ssh proxmox 'pvecm expected 1'
```

Not persistent — reverts on reboot. Safe only while the other node is genuinely off; never on both nodes at once (split-brain).

---

## Privileged vs unprivileged

**Default to unprivileged (`--unprivileged 1`).** Root inside maps to an unprivileged host UID, so a container escape is not automatically host root.

**Verified on this node:** an unprivileged CT retains `cap_net_admin`, `cap_net_raw`, and `cap_net_bind_service` in its namespace. Tested successfully inside an unprivileged container:

- binding UDP/67 (privileged port)
- opening an `AF_PACKET` socket
- `SO_BINDTODEVICE`
- `dnsmasq` initializing its DHCP engine

So **Pi-hole DHCP works unprivileged** — do not reach for a privileged container for that reason. Much guidance online says otherwise; it is outdated for PVE 9.

Privileged (`--unprivileged 0`) is only needed for things like mounting NFS/CIFS inside the CT, or some hardware passthrough. Prefer fixing it with `--features` first:

```bash
--features nesting=1          # Docker/podman inside the CT, systemd nesting
--features nesting=1,keyctl=1 # some Java/systemd services
--features mount=nfs          # NFS mounts inside
```

---

## Gathering parameters — always ask

Before creating or destructively changing a CT, gather settings with **AskUserQuestion**. Only skip a question the user already answered.

Ask in a single call (max 4 questions):

1. **Base template** — Debian 12 (default, smallest and best-trodden), or another from `pveam available`.
2. **Size** — offer tiers, not raw numbers:
   - Tiny: 1 core / 512 MB / 8 GB — DNS, Pi-hole, a small agent
   - Small: 1 core / 1 GB / 16 GB — a light web service
   - Medium: 2 cores / 2 GB / 32 GB — something with a database
3. **Networking** — DHCP vs static. If static, get the address; gw `192.168.1.1`. **Ping-check it's free first.**
4. **Privileged?** — only ask if the workload plausibly needs it; otherwise default unprivileged and say so.

Confirm the resolved plan (CTID, hostname, cores, RAM, disk, IP, storage, privileged?) before executing.

---

## List

```bash
ssh proxmox 'pct list'
ssh proxmox 'pvesh get /nodes/pve/lxc --output-format json'
```

Single CT: `pct config <ctid>`, `pct status <ctid>`.

CTs and VMs share one ID namespace — a CT cannot reuse a VM's ID. Get the next free one with `pvesh get /cluster/nextid`.

---

## Create

```bash
CTID=<next>
ssh proxmox "
  pct create $CTID local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
    --hostname <name> --memory <MB> --cores <N> --swap <MB> \
    --rootfs local-lvm:<N> \
    --net0 name=eth0,bridge=vmbr0,ip=<192.168.1.X/24,gw=192.168.1.1|dhcp> \
    --nameserver 1.1.1.1 \
    --unprivileged 1 --features nesting=1 \
    --ssh-public-keys /root/exp_key.pub \
    --onboot 1
  pct start $CTID
"
```

Notes:
- `--ssh-public-keys` takes a **file path on the node** — `scp` the key over first. Verified: SSH key auth into the CT works immediately on first boot, no extra setup.
- `--onboot 1` for anything the network depends on, so it returns when the node reboots.
- Templates go in `local` (its content list includes `vztmpl`); the rootfs goes in `local-lvm`. Different storages, easy to confuse.
- Static IP goes directly on `--net0` — there is no cloud-init layer here, unlike VMs. It applies on first boot.
- Unlike VM creation, `pct create` needs **no boot-order handling** — there is no BIOS and no PXE default to trip over.

**Then add a `~/.ssh/config` entry** (see *Keep `~/.ssh/config` in sync* above) unless the CT is a throwaway. Creation isn't done until the host is reachable by name.

### Getting a template

```bash
pveam update
pveam available --section system | grep -E "debian|ubuntu"
pveam download local debian-12-standard_12.12-1_amd64.tar.zst
pveam list local
```

`pveam download` verifies the checksum itself and reports `checksum verified` — no manual step needed (unlike ISOs in the VM skill).

---

## Update

`pct set` applies most changes **live** on a running CT — no reboot, unlike VMs:

```bash
pct set <ctid> --memory 1024 --cores 2      # takes effect immediately
pct set <ctid> --hostname new-name          # config now; visible inside after restart
pct set <ctid> --description 'purpose'
pct set <ctid> --onboot 1
pct set <ctid> --nameserver 1.1.1.1
pct set <ctid> --net0 name=eth0,bridge=vmbr0,ip=192.168.1.50/24,gw=192.168.1.1
```

Disk growth — **live, and the filesystem grows with it** (verified: 8 G → 10 G visible in `df` immediately, no reboot, no manual `resize2fs`):

```bash
pct resize <ctid> rootfs +2G
```

Cannot be shrunk.

Run commands inside without SSH:

```bash
pct exec <ctid> -- <command>       # non-interactive
pct enter <ctid>                   # interactive shell (avoid in automation)
```

Power: `pct start|shutdown|stop|reboot <ctid>`. Prefer `shutdown` over `stop`.

---

## Snapshots

**Only on `local-lvm`.** On dir storage this returns `snapshot feature is not available`.

```bash
pct snapshot <ctid> <name> --description '...'
pct listsnapshot <ctid>
pct rollback <ctid> <name>
pct delsnapshot <ctid> <name>
```

Both snapshot and rollback verified working on `local-lvm`. Suggest a snapshot before any risky change — it costs almost nothing on thin LVM.

---

## Delete

Destructive and irreversible — the rootfs goes with it.

**Always confirm first**, naming the CTID, hostname, and what's on it. Never infer a delete from an ambiguous request.

```bash
ssh proxmox "
  pct shutdown <ctid> || pct stop <ctid>
  pct destroy <ctid> --purge
"
```

A running CT cannot be destroyed. `--purge` also clears backup-job and HA references.

**Then clean up local state** — the destroy is not complete until this is done (see *Keep `~/.ssh/config` in sync* above):

```bash
# remove the Host block from ~/.ssh/config, then:
ssh-keygen -R <the CT's IP>
```

Otherwise `ssh <name>` later hangs on a dead address, or connects to whatever guest inherits that IP behind a host-key mismatch warning.

---

## Pi-hole notes

Planned use for this node — DNS + DHCP, replacing DHCP on the ISP router at `192.168.1.1`.

- **Unprivileged is fine** — DHCP capabilities verified above.
- Tiny tier is plenty: 1 core / 512 MB / 8 GB.
- **Static IP, outside the router's DHCP pool.** It cannot DHCP itself, and an address inside the pool will eventually be double-assigned.
- `--onboot 1` is mandatory — if this is down after a node reboot, nothing on the LAN gets an address.
- **Never run two DHCP servers on one L2 segment.** Clients take whichever reply lands first, producing nondeterministic failures that look like random network flakiness. Disabling DHCP on the router and enabling it in Pi-hole must happen in one sitting.
- **Do not test DHCP by actually serving the LAN.** To verify capability without handing real devices bad addresses, bind to loopback only:
  ```bash
  timeout 4 dnsmasq -d --port=0 --interface=lo --bind-interfaces \
    --dhcp-range=10.99.99.10,10.99.99.20,1h
  ```
- Keep DHCP **below** the Kubernetes cluster, not inside it. Pi-hole serving DHCP to the nodes that run the cluster that runs Pi-hole cannot cold-start.

---

## Safety rules

- **Confirm before destroying.** `pct destroy` and `pct rollback` lose data. State exactly what is lost.
- **Check quorum first** when a write fails for no clear reason.
- **Ping-check any static IP** before assigning it.
- **Respect capacity** — 4 cores, 15.9 GB. CTs are light, but the total still counts.
- **Never touch `pve-worker-01-lvm-thin`** — it belongs to the other node.
- **Keep `~/.ssh/config` in sync.** Add a `Host` entry after creating a lasting CT; remove it and run `ssh-keygen -R <ip>` after destroying one. Back the file up first — it is not in git.
- **Don't reuse an ID** — CTs and VMs share one namespace; check `pct list`, `qm list`, and `pvesh get /cluster/nextid`.
- **Never start a second DHCP server on the LAN** without the router's DHCP being disabled in the same change.
- Report what actually happened, including partial failures, rather than assuming success.
