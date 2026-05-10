# Runbook — restic backup failed

> **Triggers:** ntfy webhook from `OnFailure=` on the `restic-backup.timer`
> systemd unit on airbase. Topic: `homelab-critical`. Subject usually reads
> `restic-backup.service: Failed` with the unit's last log lines as body.
> **Severity:** critical (paging) — failed backups are silent failures, so
> escalation is harsh on purpose.
> **Audience:** on-call (me)

## TL;DR (60-second triage)

1. SSH to airbase: `ssh root@airbase.tailnet`.
2. `journalctl -u restic-backup.service -n 80 --no-pager` — what was the last error line?
3. Map the error to one of the **Common causes** below. 90 % of failures are one of three things.
4. If unfamiliar error: jump to **Investigate** and bring it to a postmortem.

## Context

The restic timer runs nightly at **02:30 Europe/Zurich** and pushes encrypted
snapshots to two repos:

- **Storage Box (offsite #1):** `sftp:u123456@u123456.your-storagebox.de:loogi-restic`
  — 1 TB Hetzner BX11. **All paths.**
- **Backblaze B2 (offsite #2):** `b2:psimaker-restic-critical:loogi-critical`
  — critical sets only (Vaultwarden DB, Paperless docs, Gitea bundles,
  Nextcloud DB dump, LOOGI ops state).

Both repos use `repokey-aes256`, password lives in
`/etc/restic/repo.password` (mode 0400, owned by root) — Ansible puts it
there from a SOPS-encrypted inventory variable.

A failed backup is one of those things that's silent if the on-failure
notification doesn't fire, so the systemd unit is configured with both
`OnFailure=ntfy-restic.service` and a Prometheus textfile-collector metric
(`restic_last_run_unix_timestamp`) which `RestricStaleBackup` alerts on if
the last successful run is >36 h old.

## Investigate

### What killed it?

```
ssh root@airbase.tailnet
journalctl -u restic-backup.service -n 200 --no-pager
systemctl status restic-backup.timer
```

Find the line right before the unit transitions to `Failed`. Restic exits
non-zero with a structured error message — `repository is locked`, `Fatal:
unable to open config file`, `server response unexpected: 507`, etc.

### Storage Box reachable?

```
ssh u123456@u123456.your-storagebox.de -p 23 ls -la
restic -r sftp:u123456@u123456.your-storagebox.de:loogi-restic snapshots --last 5
```

The Storage Box accepts SSH on port 23 (not 22). Hetzner does occasional
maintenance on these — check
[status.hetzner.com](https://status.hetzner.com/).

### B2 reachable?

```
restic -r b2:psimaker-restic-critical:loogi-critical snapshots --last 5
```

If this fails with `received 401`, the application key got rotated. The key
lives in `B2_ACCOUNT_ID` and `B2_ACCOUNT_KEY` env vars set by the systemd
drop-in at `/etc/systemd/system/restic-backup.service.d/credentials.conf`,
which Ansible regenerates from SOPS.

### Repo locked?

```
restic -r sftp:.../loogi-restic list locks
```

A leftover lock from a killed run is the single most common cause of a
"the next night's run failed too". Unlock once you're sure no other process
is touching the repo:

```
restic -r sftp:.../loogi-restic unlock
```

### Repo health

```
restic -r sftp:.../loogi-restic check --read-data-subset 5%
restic -r sftp:.../loogi-restic stats --mode raw-data
```

`check --read-data-subset 5%` is the cheap variant. Full `check --read-data`
takes ~3 hours against Storage Box and isn't necessary unless you suspect
real corruption.

### Restic timer + drift

```
systemctl list-timers restic-backup.timer
# expect: NEXT timestamp tomorrow at 02:30

systemctl cat restic-backup.timer
```

If the `OnCalendar=` value got rewritten to something weird (Ansible bug),
this is where you'd see it.

## Common causes

- **Repo lock left over.** Previous run was killed (oom, ssh disconnect,
  laptop closed mid-debug). `restic unlock` and re-run. About 60 % of the
  failures I've ever had.
- **Storage Box transient.** Hetzner maintenance, brief connectivity blip.
  Usually self-heals on the next nightly run; if not, there's normally an
  active incident on Hetzner status.
- **B2 application-key rotation drift.** Quarterly I rotate the key, and
  occasionally I forget to push the new value through SOPS → Ansible →
  airbase. The first nightly run after the rotation fails with 401.
- **Quota approaching.** See the
  [2026-02-11 prune-quota postmortem](../postmortems/2026-02-11-restic-prune-took-out-storagebox-quota.md)
  for the canonical example. The `RestricRepoSizeApproachingQuota` warning
  fires at 80 % so this should not be the *first* signal — but if you
  ignored that warning, here we are.
- **DNS hiccup at home.** AdGuardHome on airbase resolves
  `u123456.your-storagebox.de` for the local network. If AdGuardHome is
  dead, restic can't find its repo. Check `systemctl status adguardhome`.

## Mitigation

### Unlock and re-run

```
restic -r sftp:u123456@u123456.your-storagebox.de:loogi-restic unlock
systemctl start restic-backup.service
journalctl -u restic-backup.service -f
```

This kicks off a one-shot run; the timer schedule is unchanged.

### Just run it manually with verbose

When you want eyes-on for one cycle:

```
sudo -u restic /usr/local/bin/restic-run.sh --verbose
```

The wrapper sources `/etc/restic/env` and runs the same command sequence the
timer does. It tees output to `/var/log/restic-manual.log`.

### If the Storage Box is the issue

There's no graceful way to "skip Storage Box, push to B2". The wrapper does
both repos in sequence and fails fast on the first error. If Storage Box is
out for hours, edit the wrapper to skip that repo for the night, but **don't
forget to revert** — backup-skip-the-job is an awful default to leave in.

### Real fix

Postmortem for any of:

- Two consecutive nightly failures.
- One failure where root-cause analysis takes >30 min.
- Anything that touched encryption keys or quota.

## Postmortem requirement

Always for backup failures, except for "literally Hetzner Storage Box was in
incident state and the next nightly run worked fine".

## Related

- Architecture: [Backups](../architecture.md#backups)
- ADRs: [`0007-backup-restic-3-2-1.md`](../adr/0007-backup-restic-3-2-1.md)
- Past postmortems:
  [`2026-02-11-restic-prune-took-out-storagebox-quota.md`](../postmortems/2026-02-11-restic-prune-took-out-storagebox-quota.md)
- Restore-test runbook is implicitly the `restore-test.yml` Gitea workflow
  output; if the weekly restore test fails, that's the same investigative
  shape as this runbook.
