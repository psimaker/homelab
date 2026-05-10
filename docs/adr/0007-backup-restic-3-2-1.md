# ADR-0007 — Backups: restic, 3-2-1, weekly tested restore

- **Status:** Accepted
- **Date:** 2025-11-09
- **Tags:** backups, operations

## Context

A homelab that hosts other people's photos, password vaults,
documents, and calendars has the same backup obligation as any other
production system, plus the added pressure that "production-mature"
homelabs are usually distinguishable from "weekend project" homelabs by
exactly this: do they have backups, and have they tested the restore?
The data at risk includes Nextcloud (multi-hundred-GB), Immich (~400
GB), Plex metadata, Vaultwarden (small, irreplaceable), Paperless
documents (small, irreplaceable), Gitea repository bundles, and
LOOGI's operational state.

The reference standard for "real" backups is 3-2-1: three copies,
on two different media, one offsite. The reference standard for
"actually working" backups is **tested** — a backup that has never
been restored is a hope, not a backup. I have lived through one
homelab disk loss where the backup turned out to be unreadable
because the encryption key had drifted between the operator and the
script. I will not do that again.

## Decision

I am using **restic** as the single backup tool, with two encrypted
offsite repositories: a **Hetzner Storage Box BX11** as the primary
target (1 TB, ≈ €3.20/month), and **Backblaze B2** for a curated
critical-set duplicate. Retention is 14 daily / 8 weekly / 6 monthly
on Hetzner; 6 monthly / 2 yearly on B2. The local "third copy" is the
at-rest data on the source disks; restic's `prune` is gated by a
weekly schedule. **Restore tests run weekly** via
`scripts/restic-restore-test.sh`, executed by the `restore-test.yml`
workflow: it picks one repository at random, restores into a temp
directory, diffs against a known-good fixture, and fails the build on
mismatch. Eight weeks of results are kept as workflow artefacts.

The B2 critical set is: LOOGI configuration + ADRs, the Vaultwarden
database, the Paperless document store, the Nextcloud database
(snapshot only, file blobs stay on Hetzner), and Gitea's database +
repo bundles.

## Consequences

### Positive

- 3-2-1 satisfied across two providers in different jurisdictions.
- Restore is tested every week, not "the last time I checked, six
  months ago".
- restic's content-addressed deduplication keeps the storage bill
  honest even with daily snapshots.
- Encryption is per-repository, so a credential leak for one repo does
  not compromise the other.

### Negative

- Two providers means two billing relationships, two failure modes, and
  two sets of credentials in SOPS.
- A weekly restore test that picks one repo at random covers each repo
  on average every N weeks where N is the repo count — not every repo
  every week. Acceptable; I would rather have a working test for some
  than a broken test for all.
- Pruning is destructive. The runbook for prune-related issues
  (`docs/runbooks/restic-prune-failed.md`) exists for a reason.

### Neutral / known unknowns

- If Hetzner Storage Box pricing or availability changes meaningfully,
  the natural alternative is rsync.net or a second cloud provider — the
  restic side of the equation does not need to change.

## Alternatives considered

### Option A — Kopia

Newer, with a friendlier UI, built-in scheduling, and good
documentation. Rejected because the ecosystem and tooling around restic
(Helm charts, Ansible roles, monitoring exporters, the Velero
back-end) is materially larger in 2025, and I want fewer surprises.

### Option B — Duplicacy

Technically excellent. Rejected because the licence model (paid for
commercial / multi-machine use, free only for personal single-machine)
is a friction I do not want to think about every time I add a node.

### Option C — Borg

Mature, fast, well-respected. Rejected because native cloud back-ends
are not first-class — `rclone` or `borgbase` is the usual workaround,
and that is one more moving part than restic's S3-native approach.

## Notes

Linked from `architecture.md` (backups section). Revisit when:
a critical-set restore takes longer than the recovery objective for
that data; or when restic's release cadence stalls.
