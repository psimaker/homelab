# Runbook — Longhorn orphan PVC

> **Triggers:** PVC stuck in `Released` state for >24 h after the owning
> workload was deleted. Detected by the
> `LonghornOrphanedReleasedVolume` PrometheusRule.
> **Severity:** warning (digest, not paging)
> **Audience:** on-call (me)

## TL;DR (60-second triage)

1. `kubectl get pv | grep Released` — list all released PVs.
2. For each: `kubectl get pv <name> -o yaml | yq '.spec.claimRef.namespace, .spec.claimRef.name'` — what was the original PVC?
3. Decide: salvage (rebind) or delete?
4. Either way, do it consciously — don't blanket-delete because the warning is annoying. There's data on disk.

## Context

Tier-1 stateful workloads use Longhorn volumes. The default
`reclaimPolicy` on our `StorageClass` is **`Retain`**, deliberately. That
means when you delete a PVC, the underlying Longhorn volume **does not
disappear** — it stays around in `Released` state until I make an explicit
decision.

This is a feature, not a bug. The cost is that uninstalling a HelmRelease
leaves orphan PVs behind and they accumulate over months. The alert exists
to surface them so I do the cleanup deliberately rather than letting them
silently consume Longhorn replica space.

See [`docs/adr/0007-backup-restic-3-2-1.md`](../adr/0007-backup-restic-3-2-1.md)
for why we trust restic instead of Longhorn snapshots as the *primary*
recovery mechanism — that's why deleting an orphan is acceptable, even if
it had data.

## Investigate

### List the orphans

```
kubectl get pv -o wide | awk '$5=="Released"'
```

The columns to read: `NAME`, `CAPACITY`, `STORAGECLASS`, `REASON` (often
empty), and crucially `CLAIM` which still points at the deleted PVC's
namespace/name.

### What workload owned this?

```
PV=pvc-abc12345-def6-7890
kubectl get pv "$PV" -o yaml | yq '
  .metadata.annotations,
  .spec.claimRef'
```

Useful annotations:

- `pv.kubernetes.io/provisioned-by: driver.longhorn.io`
- `volume.kubernetes.io/storage-provisioner: driver.longhorn.io`

The `claimRef` tells you which PVC name and namespace the PV was bound to.
That tells you which app owned it, which tells you whether the data is
worth salvaging.

### What's on the volume?

Longhorn UI is the easiest path: `https://longhorn.tailnet/` (Tailscale
only). Find the volume by name, look at its replicas, attach it to a
node, mount it read-only, and `ls`.

CLI variant, if the UI is being slow:

```
kubectl -n longhorn-system get volume.longhorn.io/<name>
kubectl -n longhorn-system describe volume.longhorn.io/<name>

# attach for inspection (replace node):
kubectl -n longhorn-system patch volume.longhorn.io/<name> \
  --type merge --subresource status -p '{"status":{"frontend":"blockdev"}}'
```

(That's manual and rare — UI is normally the right tool here.)

### Restore from restic to verify before deletion

If you're nervous about deletion, restore the data from the most recent
restic snapshot of that PVC to a temp directory and diff. This pattern is
already automated for the weekly restore-test, so reuse the script:

```
scripts/restic-restore-test.sh --target=<pvc-name> --readonly /tmp/orphan-check
```

## Common causes

- **HelmRelease was uninstalled.** I removed an app directory from
  `kubernetes/apps/`, Flux pruned the release, the PVC the chart had
  declared got deleted, and Longhorn's `Retain` policy preserved the PV.
- **A migration to a new chart version that renamed the PVC.** Some
  Longhorn-backed workloads (Loki, Tempo) generate PVC names from
  StatefulSet identity. A chart rename leaves the old StatefulSet's PVCs
  behind, freshly Released.
- **A namespace was deleted.** Deleting a namespace cascades to PVCs but
  not to PVs (because of `Retain`).

## Mitigation

### Decision matrix

| Situation                                                              | Action                                       |
| ---------------------------------------------------------------------- | -------------------------------------------- |
| App is gone forever, restic has a recent backup of its data            | Verify restic has it, then delete the PV     |
| App is gone forever, no restic backup ever existed                     | Mount, audit, decide. Don't bulk-delete.     |
| App was renamed/moved, want to bind to a new PVC                       | Salvage (see below)                          |
| The PV claims to be Released but the workload still exists and is sad  | The "delete" was accidental — re-bind        |

### Delete cleanly

```
# 1. (Optional but I always do it) make a final restic-style dump
#    via Longhorn's "Backup" feature, just for psychological insurance:
#    Longhorn UI → Volumes → Create Backup → S3 target
#    (this hits Hetzner Object Storage, not the restic Storage Box)

# 2. Then:
kubectl delete pv pvc-abc12345-def6-7890

# 3. Confirm the underlying Longhorn volume is gone:
kubectl -n longhorn-system get volumes.longhorn.io
```

### Salvage (rebind)

```
# 1. Drop the claimRef so it doesn't insist on the old PVC:
kubectl patch pv pvc-abc12345-def6-7890 \
  --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'

# 2. Create a new PVC in the destination namespace that references this PV
#    by volumeName:
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-restored-claim
  namespace: my-app
spec:
  storageClassName: longhorn
  volumeName: pvc-abc12345-def6-7890
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi   # MUST match the PV's capacity
EOF
```

### "Just stop the warning"

This warning isn't paging — it's in the Tier-1 daily digest. Don't silence
it; do the cleanup, even if takes 15 minutes per orphan. Silencing this
defeats the entire point of the `Retain` policy.

## Postmortem requirement

A postmortem isn't usually needed — this is normal cleanup. The exception
is "I deleted the wrong PV and lost data", at which point yes, postmortem,
plus the restic restore-test gets exercised in anger.

## Related

- Architecture: [Backups](../architecture.md#backups),
  [Day-2 operations — Decommissioning](../architecture.md#day-2-operations)
- ADRs: [`0007-backup-restic-3-2-1.md`](../adr/0007-backup-restic-3-2-1.md)
