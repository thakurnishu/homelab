# The SSH host inventory moved

`config.homelab` used to live here and was symlinked to `~/.ssh/config.homelab`.
**It now lives in the dotfiles repo:**

```
~/.dotfiles/dotfiles/ssh/config.homelab
```

`~/.ssh/config.homelab` is a home-manager out-of-store symlink to that path —
out-of-store deliberately, so the file stays writable and the Proxmox skills can
edit it.

## Why it moved

Keeping the inventory beside the tooling that creates the guests was the original
argument, and it was a reasonable one. What killed it was a failure mode found
while stress-testing the arrangement:

`~/.ssh/config` pulls the file in with `Include ~/.ssh/config.homelab`. An
out-of-store symlink is an **absolute path**, so moving, renaming, or
re-checking-out this repo dangles it — and **ssh skips a dangling or missing
`Include` silently**. Verified:

```
working    ssh -G pihole -> hostname 192.168.1.111   rc=0
dangling   ssh -G pihole -> hostname pihole          rc=0, nothing on stderr
```

The failure isn't "ssh is broken", which would at least be obvious. It's the
homelab aliases quietly not resolving while git and everything else keep working,
with nothing pointing at the cause.

That was documented in three places rather than fixed. Moving the file removes the
failure class instead: one repo owns every file its own `~/.ssh/config` Includes.
The cost is that intent is now split across two repos — a documentation problem,
which is the kind that stays visible. Hence this file.

## Do not recreate a copy here

A second copy of an inventory is worse than none: nobody can tell which is
authoritative, and this one would drift the moment a guest changes. The skills in
`.claude/skills/proxmox-{vm,ct}/` point at the dotfiles path, and an agent editing
a copy here would change a file nothing reads — the same silent-success shape the
move was meant to eliminate.
