# Postmortem — 2026-02-11 — restic prune hit Storage Box quota mid-flight, nightly backup failed

## At a glance

| Field | Value |
| --- | --- |
| **Severity** | major (no production user impact, but every backup tier failed simultaneously for one cycle, which is the kind of thing that ends a homelab in the worst case) |
| **Duration** | 04:22 (from prune start to fully recovered repo, with a successful nightly backup confirmed the next night) |
| **Customer impact** | None directly user-facing. The 2026-02-11 nightly backup failed, leaving an 18-hour gap in the offsite snapshot chain. Vaultwarden, Paperless, Gitea, Nextcloud, and Immich data did not get an offsite copy that night. (B2 offsite for the critical-only set was unaffected, see below.) |
| **Detected via** | systemd `OnFailure=` ntfy push from `restic-backup.service` at 02:54 UTC, then a follow-up Storage Box quota-exceeded email from Hetzner at 03:11 UTC |
| **Detected at** | 2026-02-11 02:54 UTC |
| **Resolved at** | 2026-02-11 07:16 UTC (repo unlocked, prune re-run on a smaller subset, next nightly succeeded) |

## Timeline (UTC)

- **2026-02-11 02:30** — `restic-backup.timer` fires, runs the wrapper.
  Wrapper calls `restic backup --tag nightly` on the Storage Box repo.
- **02:31** — backup uploads start. Repo size at start: ~840 GB
  (out of 1 TB Storage Box quota).
- **02:42** — `restic backup` finishes, ~12 GB of new pack files uploaded.
  Repo size now: ~852 GB.
- **02:43** — wrapper proceeds to the prune step:
  `restic forget --keep-daily=14 --keep-weekly=8 --keep-monthly=6 --prune`.
  This rewrites pack files to remove unreferenced data — during the rewrite,
  *both* old and new pack files exist transiently.
- **02:51** — Storage Box hits its 1 TB quota mid-rewrite. The next SFTP
  write returns `failure: write failed (no space left on device)`. restic
  errors out. The repo is left with a stale lock and an interrupted
  prune state.
- **02:54** — `restic-backup.service` exits non-zero. systemd
  `OnFailure=ntfy-restic.service` fires. ntfy push to phone subject:
  *"restic-backup.service: Failed (exit code 1) — see journalctl"*.
- **02:55** — I'm asleep.
- **03:11** — Hetzner sends a quota-exceeded notification email to the
  account address. Also doesn't wake me.
- **07:02** — I wake up. Coffee. See three notifications.
- **07:05** — `ssh root@airbase.tailnet`,
  `journalctl -u restic-backup.service -n 80`. The error is clear:
  `server response unexpected: 507 Insufficient Storage`.
- **07:08** — `restic -r sftp:.../loogi-restic stats --mode raw-data`.
  Repo claims 920 GB but the Storage Box dashboard shows 1.00 TB used.
  The discrepancy is the in-flight prune's transient extra files.
- **07:11** — `restic -r sftp:.../loogi-restic list locks` shows one lock,
  age ~4 h. `restic unlock` clears it.
- **07:13** — `restic check --read-data-subset 1%`. Comes back clean. The
  data integrity is fine; we just have leftover pack files to clean up.
- **07:14** — `restic prune --max-unused=10G` to finish what got interrupted,
  with a budget-friendly threshold so it doesn't try to rewrite everything
  again. Frees ~80 GB.
- **07:16** — Repo size: 768 GB. Healthy. Storage Box at 78 % of quota.
- **07:18** — I look at *why* the repo had grown so much. Compare to last
  month's snapshot from the size-tracking metric: end of January was
  ~720 GB. So we grew ~120 GB in 11 days. That's not normal.
- **07:24** — `restic stats latest --mode raw-data` and a path-by-path
  breakdown with `restic snapshots --json | jq '...'` shows
  `/mnt/hdd/library/books` is now 142 GB — and it shouldn't be in the
  backup set at all. I check the include-list config in
  `ansible/roles/restic/defaults/main.yml`: yep, two weeks ago I added
  `/mnt/hdd/library` for an unrelated purpose, accidentally pulling
  `books` along with it.
- **07:31** — Open a PR to remove `/mnt/hdd/library/books` from the
  include-list (we have a separate, less-frequent backup for the books
  library).
- **07:36** — Merge the PR after review. Ansible runs from
  `ansible-apply.yml`, push the new include-list to airbase.
- **07:42** — Manually run `restic forget --path /mnt/hdd/library/books
  --tag nightly --prune` to actually remove the offending data from the
  repo.
- **22:06** — Skip the 22:30 manual sanity-rerun, let the regular nightly
  fire at its normal slot.
- **2026-02-12 02:30** — Nightly runs. Succeeds. Repo size: 612 GB.
  ntfy push subject changes back to *"restic-backup.service: completed"*.

## Summary

The Hetzner Storage Box hit its 1 TB quota in the middle of a `restic
prune`. The prune phase was interrupted, leaving a stale lock and
half-rewritten pack files. The deeper cause was that I'd accidentally
added a 142 GB `books` library to the backup include-list two weeks
prior in an unrelated config refactor and didn't notice the size growth.
Recovery was straightforward (unlock, finish the prune, fix the
include-list), but the offsite snapshot chain has an 18 h gap for that
day, and the failure mode itself — "I quietly grew the backup until it
broke" — is the kind of thing that should never go unnoticed for two
weeks.

## Impact

- **Direct backup impact:** the 2026-02-11 nightly to Hetzner Storage Box
  failed. 18-hour gap in the offsite snapshot chain. Last successful
  backup before that was 2026-02-10 02:42; next successful one was
  2026-02-12 02:42.
- **B2 offsite (critical-only set) was unaffected:** the wrapper runs
  Storage Box first, B2 second, and the failure on Storage Box stopped
  execution before B2 even started. Importantly this means the B2 tier
  *also* had an 18 h gap. So both offsite copies missed a night, not just
  one. That's a worse outcome than I'd modelled.
- **No data loss.** Source data on airbase was untouched. All previous
  snapshots remained intact and verifiable.
- **No user-visible impact.** This was a backup-pipeline incident, not a
  service incident.

## Root cause

There are two layers.

**Proximate cause:** the wrapper script ran `restic forget --prune`
immediately after `restic backup`. `--prune` rewrites pack files to
exclude unreferenced data — during the rewrite, both the old and new
pack files exist transiently in the repository. With the repository
already at ~85 % of the 1 TB Storage Box quota, the prune's transient
expansion pushed us over the quota line and the SFTP write failed
mid-rewrite.

**Deeper cause:** the repo was at 85 % of quota in the first place
because the backup had been silently growing. Two weeks earlier, while
refactoring the Ansible role for the bookmark backup, I added
`/mnt/hdd/library` to the restic include-list, intending only the
`bookmarks` subpath. The include-list took the parent directory at face
value and started backing up `/mnt/hdd/library/books` (142 GB of EPUBs
and PDFs) as well. I had no alerting on "backup repo grew unexpectedly",
so this went unnoticed for 11 days.

The wrapper had no defence against this either: there was no pre-flight
check of "would running this prune push us over quota?", no minimum
free-space requirement before starting, and no observation of the
include-list's *expected* total size against the *actual* repo size.

## What went well

- ntfy `OnFailure=` worked. The backup didn't fail silently, even if I
  was asleep when the page came in.
- Repository integrity was fine. `restic check` verified the data wasn't
  corrupted — just the metadata had a stale lock and there were leftover
  pack files. Recovery was a 4-line shell sequence, not "rebuild from
  zero".
- Once I identified the bloat source, the fix was a one-line config
  change shipping through the normal Ansible PR pipeline. No special
  one-off scripts.
- Postmortem-time reasoning revealed a *modelling* error I hadn't
  realised: I'd assumed Storage Box and B2 failures were independent.
  They're not, because the wrapper runs them sequentially with
  fail-fast. That insight is more valuable than the immediate fix.

## What went wrong

- The page was non-actionable while I was asleep, but I'd configured
  ntfy `homelab-critical` to push at full volume regardless of quiet
  hours. It pushed three times. I slept through it. Outcome: 4 h between
  failure and start of recovery.
- I'd added 142 GB to the backup set 11 days earlier and had no signal
  about it. Backup growth is the kind of thing that should be observed.
- Both offsite tiers missed the same night because the wrapper's
  fail-fast semantics are wrong for an "is it backed up at all" goal —
  Storage Box failing should not block the B2 attempt.
- The wrapper had no "minimum free space" pre-flight gate before
  starting a prune. Restic itself doesn't enforce one (it can't,
  reasonably, without knowing the destination's quota model).
- The Hetzner quota-exceeded email came in at 03:11 UTC, separately from
  the ntfy push, and arrived at an account I check rarely. That signal
  could have been useful 4 hours earlier if I'd routed it.

## What we got lucky on

- The `restic check` after recovery came back clean. If the
  interrupted-prune state had corrupted the repo metadata, we'd have
  been looking at a partial restore from B2 and a re-init of the Storage
  Box repo from zero, which is a multi-day operation.
- Storage Box's 507 was a clean error, not a silent half-write.
  Hetzner's SFTP server refused the write rather than accepting and
  truncating, which preserved the existing repo's integrity.
- The bloat was `books`, which has its own backup stream elsewhere. If
  it had been 142 GB of something genuinely irreplaceable I hadn't
  intended to back up here, recovery from that source would have been
  awkward.
- B2 was at 18 % of its (1 TB) quota, with plenty of headroom. The
  parallel-quota story on B2 is fine for the foreseeable future.

## Action items

- [x] **me** — Stagger `forget`/`prune` from `backup` in the timer schedule. `backup` runs nightly at 02:30; `forget --prune` now runs only on Sundays at 04:30 — 2026-02-12 — landed in commit `5fa823`.
- [x] **me** — Wrapper: run B2 even if Storage Box fails, log both outcomes — 2026-02-12 — `scripts/restic-run.sh` now uses `set +e` per repo with separate exit-code aggregation.
- [x] **me** — Add Prometheus alert `RestricRepoSizeApproachingQuota` at 80 % of Storage Box quota (warning) and 92 % (critical) — 2026-02-13 — alert in `kubernetes/infrastructure/observability/restic-alerts.yaml`.
- [x] **me** — Ansible role: compute total backup-source size from include-list at apply time, warn if estimated repo size would exceed 70 % of target quota — 2026-02-15 — implemented in `ansible/roles/restic/tasks/preflight.yml`.
- [x] **me** — Route Hetzner Storage Box quota-warning emails to the same ntfy topic as the systemd failure — 2026-02-14 — done via the `mail-to-ntfy.service` shim on airbase.
- [ ] **me** — Decide on always-allocating a Storage Box upgrade (BX21, 5 TB) vs. tightening retention — 2026-Q3 — [git.psimaker.org/umut.erdem/homelab#187](https://git.psimaker.org/umut.erdem/homelab/issues/187).
- [ ] **me** — Run a planned restic-restore-test that exercises the *recovery from quota-exceed* path explicitly, not just the happy-path restore — 2026-Q2 — [#188](https://git.psimaker.org/umut.erdem/homelab/issues/188).
- [x] **me** — Add a check in the weekly `restore-test.yml` workflow that diff's the include-list against the previous run's stats — 2026-02-20.

## Lessons

The first lesson is small and concrete: prune is not a no-op on disk.
`restic forget --prune` rewrites packs and during the rewrite the repo
is *transiently larger* than steady state. Any quota with less than
~10 % headroom over the steady-state size will be hit by a prune at
some point. This is documented in the restic FAQ and I had not internalised
it. I do now.

The second lesson is structural: I had been treating the offsite tier
as a single redundancy unit ("backups are backed up"). They aren't,
because they're behind the same wrapper that fails fast on the first
target. Even a careful 3-2-1 plan can collapse into a 0-0-1 reality if
the orchestration layer is naive about independence between tiers. The
fix is straightforward (don't bail out of B2 when Storage Box fails),
but the realisation that I was modelling the system wrong is more
valuable than the fix. I should be looking at *every* "two of these,
for redundancy" arrangement in the homelab and asking whether the
orchestration layer treats them as independent or as a chain.

The third lesson is about silent growth. The most embarrassing line in
the timeline above is *"I'd accidentally added /mnt/hdd/library/books
to the include-list two weeks prior in a config refactor, and didn't
notice the size growth."* That's not just a missing alert — it's a
missing review-time check. Adding a `RestricRepoSizeApproachingQuota`
alert is the easy fix; the harder fix is making the *intent* of the
include-list visible to me at PR time, so I see "this PR will start
backing up 140 GB of new data" before it lands. That's the second action
item I owe and the one I'm least sure I'll get right on the first try.
