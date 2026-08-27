---
name: proxmox-vm
description: Manage VMs on the homelab Proxmox node — list, create, update, and delete. Use whenever the user asks to spin up / provision / build a VM, list or check VMs, resize or reconfigure a VM (CPU, RAM, disk), or destroy / remove a VM on Proxmox. Also triggers on "pve", "hypervisor", "qm", "new server for X", "clone a template".
---

# Proxmox VM management

Manage QEMU VMs on the homelab Proxmox node over SSH.

## Connection

All operations run over SSH as root using a dedicated key:

```bash
ssh proxmox '<command>'
```

`proxmox` (and the synonym `pve`) is an alias in `~/.ssh/config`:

```
Host proxmox pve
  HostName 192.168.1.110
  User root
  Port 22
  IdentityFile ~/.ssh/proxmox
```

If the alias is missing — a fresh machine, or a rebuilt `~/.ssh/config` — either add the block above or fall back to the explicit form, which is equivalent:

```bash
ssh -i ~/.ssh/proxmox root@192.168.1.110 '<command>'
```

**Scripts should keep the explicit `-i` form** so they run on machines without the alias; the alias is for interactive use and documentation.

### Keep `~/.ssh/config` in sync — part of every create and delete

Creating or destroying a VM is not finished until `~/.ssh/config` matches reality. A config full of entries for VMs that no longer exist is worse than no entries at all: `ssh oldbox` hangs on a dead address, and once an IP is recycled the stale entry points at the wrong machine.

**Always back up first**, since this file is not in git:

```bash
cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d-%H%M%S)
```

**After creating** a VM that will stick around — once it's verified reachable, not before:

```bash
cat >> ~/.ssh/config <<'EOF'

# VM <vmid> — created <date>
Host <name>
  HostName 192.168.1.<X>
  User <ciuser>
  Port 22
  IdentityFile ~/.ssh/proxmox
EOF
ssh -o BatchMode=yes -o ConnectTimeout=8 <name> 'hostname'   # confirm it works
```

Skip this for throwaway or test VMs — only add entries for things that will outlive the session.

**After destroying** a VM, remove its entry and its host key:

```bash
# 1. drop the Host block (verify by eye before and after — do not blind-delete)
python3 - <<'PY'
import re, pathlib
p = pathlib.Path.home() / ".ssh/config"
s = p.read_text()
# removes an optional preceding comment line, the Host line, and its indented body
s2 = re.sub(r"(?m)^(?:#[^\n]*\n)?Host <name>\n(?:[ \t]+[^\n]*\n)*", "", s)
p.write_text(s2)
print("removed" if s2 != s else "no matching entry found")
PY

# 2. clear the host key, or a recycled IP later gives a scary mismatch warning
ssh-keygen -R 192.168.1.<X>
```

The pattern matches a single-name `Host` line. An entry declaring synonyms (`Host proxmox pve`) will report *no matching entry found* — edit those by hand.

`ssh-keygen -R` matters more than it looks: reusing that IP for a different machine otherwise produces `REMOTE HOST IDENTIFICATION HAS CHANGED`, which reads like an attack rather than a recycled address.

**When changing a VM's IP**, update `HostName` in the entry and run `ssh-keygen -R` on the *old* address.

**Bash sandbox:** this host is on the LAN, and the default Bash sandbox blocks outbound network. Every `ssh` call to the node needs `dangerouslyDisableSandbox: true`, or it fails with a misleading "closed/filtered" or connection error.

## Node facts (verified)

| Item | Value |
|---|---|
| Node name / IP | `pve` / `192.168.1.110` |
| Version | Proxmox VE 9.0.3 |
| Resources | 4 cores, 15.9 GB RAM |
| Bridge | `vmbr0` → `192.168.1.0/24`, gw `192.168.1.1` |
| Cloud template | VMID **9000** `ubuntu-24.04-cloud` |
| ISO | `pve-harddisk-filesystem:iso/ubuntu-24.04.4-live-server-amd64.iso` |

Storage:

| Name | Type | Use |
|---|---|---|
| `pve-harddisk-filesystem` | dir, 480 GB | **default** — images, ISOs, snippets; qcow2 → snapshots + linked clones |
| `local-lvm` | lvmthin, 148 GB | alternative for VM disks |
| `local` | dir, 71 GB | ISO/backup only, no `images` content |
| `lvmtest` | lvm | inactive — do not use |
| `pve-worker-01-lvm-thin` | lvmthin | belongs to the **other** node — do not use |

### Quorum caveat — read this when writes fail

This is a 2-node cluster and the second node is usually powered off. Without quorum, `pmxcfs` remounts `/etc/pve` **read-only** and every write fails, often with a confusing `Permission denied` rather than anything mentioning quorum.

Check and fix:

```bash
ssh proxmox 'pvecm status | grep -E "Total votes|Quorum:|Activity"'
# If "Activity blocked" appears, or Quorum > Total votes:
ssh proxmox 'pvecm expected 1'
```

`pvecm expected 1` is **not persistent** — it reverts on reboot. It is safe only while the other node is genuinely powered off; never run it on both nodes when they are isolated from each other, or `/etc/pve` will diverge (split-brain). If a VM operation fails for no obvious reason, check quorum *first*.

---

## Gathering parameters — always ask

Before creating or destructively changing a VM, gather settings with **AskUserQuestion**. Do not silently assume. Only skip a question when the user already stated that value in their request.

Ask create parameters in a single AskUserQuestion call (up to 4 questions), typically:

1. **Provisioning method** — Cloud-init clone (recommended) vs ISO install.
2. **Size** — offer concrete tiers rather than asking for raw numbers:
   - Small: 1 core / 1 GB / 10 GB
   - Medium: 2 cores / 2 GB / 20 GB
   - Large: 4 cores / 4 GB / 40 GB
   Warn if the total across running VMs would exceed 4 cores / 15.9 GB.
3. **Networking** — DHCP vs static IP. If static, ask for the address; default gateway `192.168.1.1`.
4. **Storage** — default `pve-harddisk-filesystem` unless there's a reason otherwise.

Ask for the **VM name** and **static IP** in plain text if not already given; those are free-form and don't fit multiple choice.

Always confirm the resolved plan (VMID, name, cores, RAM, disk, IP, storage) before executing.

---

## List

```bash
ssh proxmox 'qm list'
```

Richer output, including which entries are templates (`"template":1`):

```bash
ssh proxmox 'pvesh get /nodes/pve/qemu --output-format json'
```

Single VM detail: `qm config <vmid>` and `qm status <vmid>`.

Note `qm list` shows templates alongside VMs with no marker — check the `template` field via `pvesh` when the distinction matters.

---

## Create

### Method A — clone the cloud-init template (preferred)

Fast (~20 s to SSH-able), no console interaction. This is the default unless the user wants a manual install.

```bash
VMID=<next>            # get with: pvesh get /cluster/nextid
NAME=<name>
ssh proxmox "
  qm clone 9000 $VMID --name $NAME --full
  qm set $VMID --ciuser <user> --sshkeys /root/authorized_pubkey \
    --ipconfig0 ip=<192.168.1.X/24,gw=192.168.1.1|ip=dhcp> \
    --nameserver 1.1.1.1 --memory <MB> --cores <N>
  qm resize $VMID scsi0 +<N>G
  qm start $VMID
"
```

Notes:
- The template's base disk is only 3.5 GB — **always `qm resize`** to the requested size. Cloud-init grows the root filesystem automatically on first boot.
- `--sshkeys` needs a **file path on the node**. `scp` the public key over first, or write it to a temp file; do not attempt to pass the key inline.
- `--full` gives an independent disk. Omit it for a linked clone (faster, less space, but tied to the template).
- Set `--ciupgrade 0` if you want to skip the first-boot package upgrade.

Verify it came up:

```bash
ssh proxmox "qm status $VMID"
ssh -i ~/.ssh/proxmox <user>@<ip> 'cloud-init status'   # expect: status: done
# ^ the new VM has no ~/.ssh/config alias yet — add one once it's confirmed working
```

`cloud-init status` reports `running` for roughly 30–60 s after SSH first answers; wait for `done` before declaring success.

**Then add a `~/.ssh/config` entry** (see *Keep `~/.ssh/config` in sync* above) unless this is a throwaway VM. Creation isn't done until the host is reachable by name.

### Method B — install from ISO

For a manual install; the user must click through the installer via the web console at `https://192.168.1.110:8006`.

```bash
ssh proxmox "
  qm create $VMID --name $NAME --memory <MB> --cores <N> \
    --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single --ostype l26 \
    --agent 1 --cpu host --machine q35 --bios seabios
  qm set $VMID --scsi0 pve-harddisk-filesystem:<N>
  qm set $VMID --ide2 pve-harddisk-filesystem:iso/ubuntu-24.04.4-live-server-amd64.iso,media=cdrom
  qm set $VMID --boot 'order=scsi0;ide2'
  qm start $VMID
"
```

**Critical:** without an explicit `--boot order=...`, Proxmox defaults to `boot: order=net0` and the VM will attempt PXE and fail to boot. Always set boot order when a disk is attached.

Use `seabios`, not `ovmf` — `ovmf` additionally requires an EFI disk (`--efidisk0 <storage>:0,efitype=4m`), which is an easy step to forget and a confusing failure.

---

## Update

Most properties are changed with `qm set` and apply on next boot; CPU/RAM changes need a stop/start unless hotplug is configured.

```bash
qm set <vmid> --memory 4096 --cores 4          # resources
qm set <vmid> --name new-name                  # rename
qm set <vmid> --description 'purpose'          # note
qm set <vmid> --onboot 1                       # autostart at node boot
qm set <vmid> --ipconfig0 ip=192.168.1.50/24,gw=192.168.1.1   # cloud-init net
```

Disk growth (**cannot be shrunk**):

```bash
qm resize <vmid> scsi0 +10G
```

`qm resize` on dir-storage raw disks may print `failed: got timeout` yet still have succeeded. Always re-check with `qm config <vmid> | grep scsi0` rather than trusting the exit status.

Cloud-init changes only take effect after a **full stop and start** — a reboot from inside the guest is not enough, since the cloud-init drive is regenerated at VM start:

```bash
qm stop <vmid> && qm start <vmid>
```

Power control: `qm start|shutdown|stop|reboot <vmid>`. Prefer `shutdown` (ACPI, graceful) over `stop` (hard kill).

---

## Delete

Destructive and irreversible — the disk goes with it.

**Always confirm with the user first**, showing the VMID, name, and disk that will be destroyed. Never infer a delete from an ambiguous request.

```bash
ssh proxmox "
  qm shutdown <vmid> || qm stop <vmid>
  qm destroy <vmid> --purge
"
```

`--purge` also removes the VM from backup jobs and HA/replication config. Without it, stale references linger.

**Then clean up local state** — the destroy is not complete until this is done (see *Keep `~/.ssh/config` in sync* above):

```bash
# remove the Host block from ~/.ssh/config, then:
ssh-keygen -R <the VM's IP>
```

Leaving these behind means `ssh <name>` later hangs on a dead address, or — once Proxmox recycles that IP for a different guest — connects to the wrong machine behind a host-key mismatch warning.

A running VM cannot be destroyed — stop it first. Refuse outright to destroy template **9000** unless the user explicitly names it and confirms they intend to lose the template.

---

## Snapshots

Only on storage that supports it — `pve-harddisk-filesystem` (qcow2) does; **raw disks on LVM do not**.

```bash
qm snapshot <vmid> <snapname> --description '...'
qm listsnapshot <vmid>
qm rollback <vmid> <snapname>
qm delsnapshot <vmid> <snapname>
```

Taking a snapshot before a risky update is cheap and worth suggesting.

---

## Rebuilding the cloud template

If template 9000 is lost or needs refreshing:

```bash
ssh proxmox '
  IMG=/mnt/pve/pve-harddisk-filesystem/cloudimg/noble-server-cloudimg-amd64.img
  wget -q -O $IMG https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
  qm create 9000 --name ubuntu-24.04-cloud --memory 2048 --cores 2 \
    --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single --ostype l26 \
    --agent 1 --cpu host --machine q35 --bios seabios
  qm set 9000 --scsi0 pve-harddisk-filesystem:0,import-from=$IMG
  qm set 9000 --ide2 pve-harddisk-filesystem:cloudinit
  qm set 9000 --boot order=scsi0
  qm set 9000 --serial0 socket --vga serial0
  qm template 9000
'
```

`--serial0 socket --vga serial0` matters: Ubuntu cloud images expect a serial console, and without it the Proxmox console shows nothing.

Adding an ISO — note `pvesm download-url` is **API-only and not a `pvesm` CLI subcommand**; use `wget` into `<storage-path>/template/iso/` and verify the checksum by hand:

```bash
D=/mnt/pve/pve-harddisk-filesystem/template/iso
wget -O $D/<file>.iso <url>
echo "<sha256>  $D/<file>.iso" | sha256sum -c
```

---

## Safety rules

- **Confirm before destroying.** `qm destroy` and `qm rollback` lose data. State exactly what will be lost and get explicit agreement.
- **Check quorum first** when any write fails unexpectedly.
- **Respect capacity.** The node has 4 cores and 15.9 GB. Warn before overcommitting RAM; CPU overcommit is usually fine, RAM is not.
- **Never touch `pve-worker-01-lvm-thin`** — it belongs to the other node.
- **Keep `~/.ssh/config` in sync.** Add a `Host` entry after creating a lasting VM; remove it and run `ssh-keygen -R <ip>` after destroying one. Back the file up first — it is not in git.
- **Don't reuse a VMID** without checking `qm list` and `pvesh get /cluster/nextid`.
- Report what actually happened. If `qm resize` times out or cloud-init reports an error, say so with the output rather than assuming success.
