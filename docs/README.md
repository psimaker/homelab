# Documentation

If you're reading the homelab repo and want to understand it deeply, this is
the entry point. Everything here describes *what the system is and why*; the
per-directory READMEs elsewhere in the tree describe *how each directory is
used*.

## Architecture

[`architecture.md`](architecture.md) — the canonical design doc. Tiers,
hardware, network, GitOps, secrets, TLS, observability, backups, bootstrap.
Read this first.

## ADRs

[`adr/`](adr/) — every non-obvious decision and why. Tier-1/Tier-2 split,
Flux vs Argo, SOPS vs Vault, Pocket-ID vs Authentik, two-issuer TLS, and the
rest. New decisions land here before they land in code.

## Runbooks

[`runbooks/`](runbooks/) — what to check when alerts fire. Each
`runbook_url` annotation in Alertmanager points into this directory; if an
alert exists without a runbook, that's a bug.

## Postmortems

[`postmortems/`](postmortems/) — what broke, what we learned. Blameless,
timestamped, action-items tracked to closure.

---

> If a directory has its own README, that's how the directory is *used*.
> The docs here explain *what the system is*.
