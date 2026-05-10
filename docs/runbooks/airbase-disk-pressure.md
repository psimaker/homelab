# Runbook — airbase disk pressure

> **Triggers:** `NodeFilesystemAlmostOutOfSpace{node="airbase",mountpoint="/mnt/hdd"}`
> for >85 % full, OR `node="airbase",mountpoint="/"` for >80 % full.
> **Severity:** warning at 85 %, critical at 92 % (paging).
> **Audience:** on-call (me)

## TL;DR (60-second triage)

1. SSH in: `ssh root@airbase.tailnet`.
2. `df -h /` and `df -h /mnt/hdd` — confirm which mountpoint is the problem.
3. `du -sh /var/lib/docker/{containers,overlay2,volumes} 2>/dev/null | sort -h | tail` — top Docker consumers.
4. If `/mnt/hdd`: `du -sh /mnt/hdd/* | sort -h | tail` — likely Plex, Tdarr, or Immich ML.

90 % of the time the answer is one of three things — see Common causes.

## Context

airbase has two filesystems we care about:

- **`/`** on the 4 TB NVMe — system, container data (`/var/lib/docker`),
  k3s containerd, restic cache, AdGuardHome data.
- **`/mnt/hdd`** on the 16 TB HDD — bulk media (Plex, books, photos waiting
  for ingest), Tdarr work-space, periodic dumps.

Disk pressure on **`/`** is more dangerous than on `/mnt/hdd`:

- The kubelet starts evicting pods on the airbase node at 85 % (`evictionHard:
  nodefs.available<15 %`). Tier-1 workloads scheduled to airbase go into a
  reschedule loop.
- Docker can't allocate new layers, so any Tier-2 image pull fails.
- restic's local cache (`/var/cache/restic`) silently bloats; if it can't
  open a tempfile during backup, the nightly run fails — see
  [`restic-backup-failed.md`](restic-backup-failed.md).

Disk pressure on **`/mnt/hdd`** mostly means Plex transcoding stops, Tdarr
queues stall, and Immich indexing pauses. Annoying, not paging. The
warning-only threshold is intentional.

## Investigate

### Which filesystem and how bad

```
df -h
df -hi          # inodes — separate failure mode
findmnt /mnt/hdd
```

### Top consumers, fast

For `/`:

```
du -shx /var/lib/docker /var/lib/rancher /var/lib/containerd /var/log /var/cache 2>/dev/null \
  | sort -h | tail
docker system df --format 'table {{.Type}}\t{{.Total}}\t{{.Active}}\t{{.Size}}\t{{.Reclaimable}}'
```

For `/mnt/hdd`:

```
du -sh /mnt/hdd/* 2>/dev/null | sort -h | tail
# typical output:
#   12G   /mnt/hdd/tdarr-cache
#   180G  /mnt/hdd/library/books
#   1.8T  /mnt/hdd/photos-staging
#   8.9T  /mnt/hdd/plex
```

### cAdvisor in Grafana

The "Node disk by container" panel in the Beszel dashboard breaks down disk
usage per container in real time. Faster than SSH for "which container is
the offender" once you know the answer is in Docker.

### Plex transcode dir

```
ls -lh /var/lib/plex/Library/Application\ Support/Plex\ Media\ Server/Cache/Transcode/
du -sh /var/lib/plex/Library/Application\ Support/Plex\ Media\ Server/Cache/Transcode/
```

If this is >5 GB, Plex didn't clean up after a session. Server crash mid-stream
will leave gigabytes here.

### Tdarr work-space

```
du -sh /mnt/hdd/tdarr-cache
docker logs tdarr_node 2>&1 | tail -50
```

Tdarr is configured to abort if free space on `/mnt/hdd` drops below 50 GB,
but the abort path leaves partial files behind. Clean those out before
restarting.

### Immich ML model cache

```
docker exec immich_machine_learning du -sh /cache
# or from the host:
du -sh /var/lib/docker/volumes/immich_model-cache/_data
```

If we recently changed the ML model in `compose/immich/.env`, the new model
is downloaded on first use *without* deleting the old one.

### restic local cache

```
du -sh /var/cache/restic
# expected: a few GB; >10 GB means we should prune the local cache, not the remote
restic cache --cleanup
```

## Common causes

- **Plex transcode-tmp left behind after a Plex crash.** Plex Media Server
  dies mid-transcode (often during a server restart), the transcode tempfiles
  are orphaned. Can grow into tens of GB on `/`. Most common cause of root-fs
  pressure.
- **Tdarr ran out of work-space and didn't clean up.** Look in the Tdarr
  GUI: any node showing "errored" jobs leaves their staging files in
  `/mnt/hdd/tdarr-cache`. Manual prune is required.
- **Immich ML model cache after an update.** A model swap (e.g. `MCLIP_MODEL`
  changed) leaves the old model on disk. ~2-4 GB each. The chart doesn't
  prune.
- **Container logs without rotation.** Some Tier-2 stacks I never bothered to
  add `logging:` config to. `docker inspect <name> | jq '.[0].LogPath'` to
  find. Truncate carefully.

## Mitigation

### Quick wins, in priority order

```
# 1. Plex transcode dir (safe to wipe; Plex regenerates on next session)
rm -rf /var/lib/plex/Library/Application\ Support/Plex\ Media\ Server/Cache/Transcode/*

# 2. Docker prune — images, build cache, dangling volumes
docker image prune -af
docker builder prune -af
# avoid `docker volume prune` blindly; it deletes named volumes not in use

# 3. k3s containerd image prune
crictl rmi --prune

# 4. restic cache trim
restic cache --cleanup

# 5. journald
journalctl --vacuum-size=500M
```

If the node is in `DiskPressure: True` and pods are getting evicted, do
steps 1 and 5 first — they're the lowest-risk.

### "Just stop paging me"

```
amtool silence add --alertmanager.url=http://alertmanager.observability.svc:9093 \
  alertname=NodeFilesystemAlmostOutOfSpace node=airbase --duration=2h \
  --comment="Cleanup in progress"
```

### Real fix

The repeated cause across this runbook's history is **no caps on
container-managed disk areas**. The improvements I keep half-implementing:

- Plex transcode dir: bind-mount a `tmpfs` of capped size (`/dev/shm/plex-transcode`)
  — already in `compose/plex/compose.override.yml`, just need to roll it out.
- Tdarr: hard cap on `tdarr-cache` size in Tdarr's own settings.
- Immich: scheduled cleanup of `model-cache` in the Compose's restart hook.

If the same trigger fires twice in a quarter, I owe a postmortem and an ADR
for these caps.

## Postmortem requirement

If pods got evicted (look at `kubectl get events --sort-by=.lastTimestamp -A
| grep -i evicted`), or `restic-backup.service` failed during the same window,
that's a postmortem.

## Related

- Architecture: [Hardware and topology](../architecture.md#hardware-and-topology)
- Sibling runbook: [`k3s-node-notready.md`](k3s-node-notready.md),
  [`restic-backup-failed.md`](restic-backup-failed.md)
