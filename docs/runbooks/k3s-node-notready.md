# Runbook — k3s node NotReady

> **Triggers:** `KubeNodeNotReady{node=~"edge|airbase"}` for >5 m.
> **Severity:** critical (paging)
> **Audience:** on-call (me)

## TL;DR (60-second triage)

1. `kubectl get nodes -o wide` — which node, since when, what's its `Ready` condition reason?
2. `tailscale status` from the operator laptop — is the node still reachable on the tailnet?
3. SSH in via Tailscale: `ssh root@edge.tailnet` (or `airbase.tailnet`). If you can't, jump to "tailnet hiccup" below.
4. Once on the host: `systemctl status k3s` (edge) or `systemctl status k3s-agent` (airbase).

If the kubelet is up and `journalctl -u k3s-agent --since '15 min ago'` is clean, look at disk pressure (Investigate → Disk).

## Context

Two nodes, neither replaceable on a moment's notice:

- `edge` is the k3s **server** (control plane). If it goes NotReady, the API
  is still up — but cluster scheduling and Flux reconciliation are stalled.
  Everything currently running keeps running; nothing new gets scheduled or
  rescheduled.
- `airbase` is the only **agent**. If it goes NotReady, every pod scheduled
  there enters `NodeLost`/`Terminating` and any workload with a node-affinity
  pin to airbase (Immich, things needing GPU) is offline.

A NotReady event is rare and almost always one of: kubelet crash, disk
pressure, or the tailnet between the two going sideways for long enough that
the kubelet's heartbeat to the API server times out.

## Investigate

### Confirm and identify

```
kubectl get nodes
# NAME      STATUS     ROLES                  AGE    VERSION
# edge      Ready      control-plane,master   140d   v1.31.4+k3s1
# airbase   NotReady   <none>                  140d   v1.31.4+k3s1

kubectl describe node airbase | sed -n '/Conditions/,/Addresses/p'
```

The `Conditions` table tells you which signal flipped. `Ready=False` with
`reason: KubeletNotReady` and a stale `LastHeartbeatTime` means the kubelet
isn't talking to the API server.

### Reachability

```
tailscale ping airbase.tailnet
ssh root@airbase.tailnet 'uptime; uname -r'
```

If ping works but SSH hangs, suspect a kernel hang (rare on this hardware but
has happened during a btrfs scrub) — at that point we're in physical-access
land for airbase, or `hcloud server reboot` for edge.

### kubelet status

On the affected node:

```
systemctl status k3s-agent      # airbase
systemctl status k3s            # edge
journalctl -u k3s-agent --since '30 min ago' --no-pager | tail -200
```

What I look for:

- `OOMKilled` in the journal — kubelet itself was killed, almost always
  because a workload without resource limits ate the node.
- `failed to find plugin "cilium-cni"` — the CNI binary went missing.
  Cilium's `install-cni` init container repopulates it on pod restart, but
  if Cilium itself is gone too you have a chicken-and-egg.
- `context deadline exceeded` against the API server — the tailnet between
  airbase and edge is the actual problem; kubelet is fine. Skip to "tailnet
  hiccup".

### Disk

```
df -h /var/lib/rancher /var /
df -hi                              # inodes
journalctl -k --since '30 min ago' | grep -i 'no space left'
```

If `/` is >85 % or `/var` is >80 %, k3s starts evicting pods and the kubelet
can hit `DiskPressure: True`. On airbase the usual offender is `/var/lib/docker`
(Tier-2 docker), see [`airbase-disk-pressure.md`](airbase-disk-pressure.md).

On edge, the only large consumer is k3s itself plus container image layers.
`crictl rmi --prune` reclaims a few hundred MB.

### Tailnet hiccup

If the symptom is "kubelet logs show repeated `dial tcp 100.64.0.1:6443:
i/o timeout`" and tailscale ping is also flaky:

```
# from operator laptop, with tailscale up
tailscale status
tailscale netcheck

# on the affected node
ip a show tailscale0
sudo systemctl restart tailscaled
```

The Headscale control plane runs in the cluster, so if both nodes lose the
mesh you can still recover via direct IPv4 (Hetzner public IP for edge,
your home LAN for airbase) but you'd be working without DNS-by-tailnet-name
until the mesh comes back.

## Common causes

- **kubelet OOM-killed by a runaway pod without limits.** The node hits
  cgroup-level pressure, the OOM killer picks the kubelet because its OOM
  score is comparatively benign. Fixed properly by enforcing
  `LimitRange` defaults in every namespace — partially done, see
  `kubernetes/infrastructure/policy/limitranges.yaml`.
- **Disk pressure.** Almost always Plex transcode-tmp on airbase or a runaway
  Docker volume. See [`airbase-disk-pressure.md`](airbase-disk-pressure.md).
- **Tailnet hiccup.** Surprisingly rare given how much I worried about it
  during the design — Tailscale's reconnect is solid. When it does happen,
  it's usually because my home ISP did a CGNAT churn and the relay
  selection took 90 s to stabilise.
- **kernel hang on airbase.** Has happened twice in a year. Both times during
  a btrfs scrub on `/mnt/hdd` overlapping with heavy Plex transcoding. Recovery
  is a hard reboot.

## Mitigation

### If kubelet is just stuck

```
ssh root@airbase.tailnet 'systemctl restart k3s-agent'
# or for edge:
ssh root@edge.tailnet     'systemctl restart k3s'
```

Watch the node come back:

```
kubectl get nodes -w
```

### If disk pressure

Cross-link [`airbase-disk-pressure.md`](airbase-disk-pressure.md). Quickest
win on airbase:

```
ssh root@airbase.tailnet 'docker system prune -af --volumes'
ssh root@airbase.tailnet 'rm -rf /var/lib/plex/Library/Application\ Support/Plex\ Media\ Server/Cache/Transcode/*'
```

Then make sure you have a postmortem if the wedge lasted >30 min — repeated
disk-pressure events mean we need a real cap on those directories, not just
opportunistic clean-up.

### If you can't get the node back from across the tailnet

`hcloud server reboot edge` has saved me at least once. For airbase, physical.
Both are last-resort.

## Postmortem requirement

NotReady almost always satisfies the postmortem threshold (impact >5 min on
something), so default to opening one. The exception is a clean tailnet
hiccup that auto-recovered in <10 minutes.

## Related

- Architecture: [Hardware and topology](../architecture.md#hardware-and-topology),
  [Network and identity](../architecture.md#network-and-identity)
- Sibling runbook:
  [`airbase-disk-pressure.md`](airbase-disk-pressure.md),
  [`tailscale-mesh-mtu.md`](tailscale-mesh-mtu.md)
