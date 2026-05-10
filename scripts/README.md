# scripts/

Operational helpers for the homelab. Two flavours:

- **Bootstrap** — runs once (or once per operator workstation) to bring the
  cluster from nothing to reconciling.
- **Day-2** — re-runnable utilities for routine work: SOPS encrypt/decrypt,
  age-key rotation, restore tests, snapshotting Tier-2 stacks back into
  `compose/`.

Every script:

- Uses `#!/usr/bin/env bash` and `set -euo pipefail`.
- Decomposes work into named functions; `main` at the bottom shows the order.
- Has a `--help` flag.
- Prefixes log lines with `[INFO]`, `[OK]`, `[WARN]`, `[FAIL]` (colourised
  on TTY, plain in pipes/CI).
- Prompts for confirmation on destructive steps unless `--unattended` is
  passed.

## What each script does

| Script | When to run | What it does |
| --- | --- | --- |
| [`bootstrap.sh`](bootstrap.sh) | First-deploy of the cluster, ever, or rebuilding from scratch. | Pre-flight CLI checks → `tofu apply` → wait for SSH → `ansible-playbook site.yml` → install `Secret/sops-age` → `flux bootstrap gitea` → wait for `infrastructure` to converge. |
| [`bootstrap-secrets.sh`](bootstrap-secrets.sh) | Once per operator machine, before `bootstrap.sh`. | Generates `~/.config/sops/age/keys.txt`, prints the public key, walks you through editing `.sops.yaml` and re-encrypting existing files. |
| [`sops-encrypt.sh`](sops-encrypt.sh) | Each time you add a new `*.sops.*` file. | Thin wrapper around `sops --encrypt --in-place` that runs from the repo root so `.sops.yaml` rules apply. |
| [`sops-decrypt.sh`](sops-decrypt.sh) | Inspecting an encrypted file. | Decrypts to **stdout only** — never to disk. Pipe it into `less`, `yq`, etc. |
| [`decrypt-and-source-env.sh`](decrypt-and-source-env.sh) | Loading a SOPS-encrypted `.env` for a one-shot command. | **Source** (don't execute) to export variables into the current shell. Plaintext never touches disk. |
| [`rotate-age-key.sh`](rotate-age-key.sh) | Annually (Q1 housekeeping checklist). | Steps a human through: generate new key → add as second recipient → `sops updatekeys` → patch in-cluster Secret → update CI secret → 24h verification window → remove old recipient → `sops updatekeys` → archive old key. Resume mid-flight with `--resume N`. |
| [`restic-restore-test.sh`](restic-restore-test.sh) | Weekly (driven by `restore-test.yml`) or ad hoc. | Picks one configured restic repo at random, restores a known-good fixture, diff-checks against `tests/fixtures/restic-known-good.txt`. Emits Prometheus textfile metrics. Exit 1 on diff, 2 on infra error. |
| [`airbase-snapshot.sh`](airbase-snapshot.sh) | Quarterly to re-sync `compose/` with reality. | SSHes to airbase, scp's each Tier-2 compose file, redacts secret literals to `${VAR}`, regenerates `.env.example`, writes a small `README.md` per stack. |
| [`precommit-install.sh`](precommit-install.sh) | Once per fresh clone, or after `.pre-commit-config.yaml` changes. | Installs `pre-commit` (via pipx or pip), registers the commit/push hooks, pre-fetches every hook environment so the first commit is fast. |

## Conventions

- **Path resolution.** Every script computes its own `SCRIPT_DIR` and
  `REPO_ROOT`; absolute paths are used throughout. You can run any script
  from any cwd.
- **Confirmation gating.** Anything destructive (writing the cluster, the
  encrypted files, `keys.txt`) prompts with `confirm()`. `--unattended` is
  the explicit override and is required in CI.
- **Idempotence.** Re-running `bootstrap.sh` after a successful run is safe;
  every step uses `--dry-run=client | apply -f -` or equivalent.
- **No plaintext secrets on disk.** `sops-decrypt.sh` and
  `decrypt-and-source-env.sh` materialise plaintext only in memory.
  `bootstrap-secrets.sh` writes the age private key to
  `~/.config/sops/age/keys.txt` with mode 600 — that is the one acceptable
  exception.

## Architecture context

Read [`docs/architecture.md`](../docs/architecture.md) — the "Bootstrap
sequence" and "Secrets" sections explain why these scripts exist and how
they map onto the design.
