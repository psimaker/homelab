# ADR-0010 — airbase stays bare-metal Debian, no Proxmox

- **Status:** Accepted
- **Date:** 2025-08-19
- **Tags:** infrastructure, hypervisor

## Context

`airbase` is a 16-core / 64 GB ECC tower running Debian 12 with
roughly fifty Docker Compose containers. Of those, several are real
production services (Plex, Immich, Nextcloud, Vaultwarden, Gitea) used
daily by people who would notice an outage. Storage is local: a 4 TB
NVMe for system and container data plus a 16 TB HDD for media at
`/mnt/hdd`. The setup has been continuous for several years.

A frequently-suggested "next step" in this part of the self-hosted
ecosystem is to put a hypervisor underneath: Proxmox, often as a
prerequisite for "easily" running k8s, Talos, NAS VMs, or per-stack
LXC containers. The pitch is layering, isolation, and snapshots-of-VMs.
The cost is replatforming a working host, learning a new operational
model, paying virtualisation overhead on workloads that genuinely use
the hardware (Immich's CUDA pipeline, for example), and accepting the
non-zero risk of breaking what currently works.

## Decision

`airbase` stays **Debian 12 + Docker, bare metal**. No Proxmox, no
ESXi, no XCP-ng. The host is managed by Ansible (kernel sysctls,
fail2ban, node_exporter, restic timer); workloads live in Docker
Compose under `compose/`. The k3s agent that participates in Tier-1
runs as a systemd-managed binary on the same host, sharing the kernel
with Docker but using a separate containerd snapshotter
(`overlayfs`-pinned, so the two do not fight).

## Consequences

### Positive

- Zero migration risk for the fifty existing containers. The whole
  Tier-2 stack keeps running through and after this decision.
- GPU passthrough is a non-issue — the GPU is on the host, both Docker
  and the k3s agent see it directly.
- Backups and storage work the way they always have. `/mnt/hdd` is a
  filesystem, not a virtual disk.
- One kernel to update, one boot to debug at 2 AM.

### Negative

- No hypervisor-level snapshots before risky upgrades. Mitigated by
  ZFS-style snapshots on individual datasets (where applicable) and
  by restic backups for everything else.
- "Spinning up another VM" is not a one-click action. If I ever need
  isolation for a workload that genuinely warrants it, I will run it
  in a real container, not invent a hypervisor for the occasion.
- A second Linux user on this machine would have direct host access,
  not a confined VM. Acceptable: there is no second user.

### Neutral / known unknowns

- If a future workload genuinely requires VM-level isolation (a
  Windows instance for some specific tool, for example), the right
  answer is probably KVM/libvirt on this same host rather than
  Proxmox-ifying everything.

## Alternatives considered

### Option A — Proxmox VE under everything

Move to Proxmox, run Docker in a VM, k3s in another, NAS in a third.
Rejected because it pays a substantial migration cost and ongoing
operational tax to gain "more layers". The actual benefits (live
migration, VM snapshots) do not apply: there is one host, and snapshots
of multi-TB VM disks are not a great backup primitive.

### Option B — Replace Docker with Talos + k8s on `airbase` too

Make `airbase` a single-node Talos cluster, put everything on
Kubernetes. Rejected for the same reasons as ADR-0001's "migrate
everything to Kubernetes": real production state, replatforming risk,
no operational benefit for this workload class.

## Notes

Linked from `architecture.md` ("Things deliberately not done") and
ADR-0001. Revisit when: a workload arrives that genuinely requires
VM-level isolation; or when the host's hardware needs replacement and
a fresh build is on the table anyway.
