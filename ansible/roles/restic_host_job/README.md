# `restic_host_job`

Installs `restic`, configures two repositories (Hetzner Storage Box +
Backblaze B2), drops a backup script, and wires a systemd timer.

## What it does

- Installs `restic` from the GitHub release (the Debian package lags).
- Renders an environment file with all repo URLs, the encryption password,
  the B2 credentials, and the ntfy failure URL — file mode 0600, every task
  with `no_log: true`.
- Initialises both repositories on first run (idempotent — skip if
  `restic cat config` succeeds).
- Renders `/usr/local/bin/restic-backup` with:
  1. Primary backup of `restic_backup_paths` (default: `/data/loogi`,
     `/data/gitea`, `/data/vaultwarden`, `/data/paperless`, `/data/n8n`,
     `/data/syncthing`) to Hetzner Storage Box.
  2. Critical-only backup to B2 (`restic_b2_critical_paths`).
  3. `restic forget --prune` with retention 14 daily / 8 weekly /
     6 monthly on primary, 6 monthly / 2 yearly on B2.
  4. POST to `ntfy_failure_url` on any non-zero exit.
- Excludes huge / recoverable trees (`/data/plex`, `/data/rr/data`,
  `/mnt/hdd`, the Nextcloud blob volume) and patterns (`*.tmp`, `*.log`,
  `__pycache__`).
- Installs `restic-backup.service` + `restic-backup.timer` and enables
  the timer at `*-*-* 03:30:00 Europe/Zurich`.

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `restic_backup_paths` | tier-2 list | Override per host. |
| `restic_exclude_paths` | tier-2 excludes | Plex, mnt/hdd, etc. |
| `restic_keep_daily/weekly/monthly` | 14/8/6 | Forget policy. |
| `restic_repository_primary` | inv | Hetzner Storage Box SFTP URL. |
| `restic_repository_secondary` | inv | B2 bucket URL. |
| `restic_password` / `_b2_*` / `ntfy_failure_url` | (SOPS) | Secrets. |

## Tags

`restic`, `restic_host_job`.

## Restore

The script does not include a restore wrapper — restoring is interactive by
nature (you pick a snapshot, you pick paths, you pick a target).
The weekly restore-test workflow
([`scripts/restic-restore-test.sh`](../../../scripts/restic-restore-test.sh))
exercises the path automatically. See
[`docs/architecture.md`](../../../docs/architecture.md#backups) for the 3-2-1
narrative.
