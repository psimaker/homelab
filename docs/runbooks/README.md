# Runbooks

This directory holds the on-call runbooks for the homelab. Every Prometheus
alert with `severity: critical` or `severity: warning` should have a
`runbook_url` annotation pointing at one of these files. If an alert
doesn't have one, it's a bug in the alert — file it and add the runbook.

The audience is **future-me at 2 AM**. Each runbook is structured the same
way (see [`_template.md`](_template.md)):

1. **TL;DR** — three or four checks I can do without thinking.
2. **Context** — why the alert matters and what's affected.
3. **Investigate** — exact commands to run, with expected output.
4. **Common causes** — ordered by frequency, not alphabetically.
5. **Mitigation** — both "stop the page" and "fix it for real".
6. **Postmortem requirement** — when this fires, do I owe a writeup?
7. **Related** — back-links to architecture sections, ADRs, past incidents.

Conventions:

- Real commands, no `# TODO replace with actual command`. If a command is
  aspirational, mark it with `# TODO` and put a date next to it.
- One operator (me). First-person singular, no plural-corporate-we.
- Cross-link aggressively to [`docs/architecture.md`](../architecture.md)
  and [`docs/adr/`](../adr/) so a future-me can rebuild the mental model.
- Past postmortems show up under "Related" in the runbook that fired.

## Runbook index

| Runbook                                                              | Trigger                                          | Severity            | Last updated |
| -------------------------------------------------------------------- | ------------------------------------------------ | ------------------- | ------------ |
| [LOOGI availability](loogi-availability.md)                          | `LoogiAvailabilityHighBurnFast` / `BudgetExhausted` | critical (paging) | 2026-05-10   |
| [LOOGI p95 latency](loogi-latency-p95.md)                            | `LoogiLatencyP95Exceeded`                        | critical (paging) when fast-burn | 2026-05-10 |
| [k3s node NotReady](k3s-node-notready.md)                            | `KubeNodeNotReady`                               | critical (paging)   | 2026-05-10   |
| [restic backup failed](restic-backup-failed.md)                      | systemd `OnFailure=` ntfy webhook                | critical (paging)   | 2026-05-10   |
| [cert renewal stuck](cert-renewal-stuck.md)                          | `CertManagerCertExpiringSoon` (<14 d / <7 d)     | warning → critical  | 2026-05-10   |
| [airbase disk pressure](airbase-disk-pressure.md)                    | `NodeFilesystemAlmostOutOfSpace{node="airbase"}` | warning → critical  | 2026-05-10   |
| [Longhorn orphan PVC](longhorn-orphan-pvc.md)                        | `LonghornOrphanedReleasedVolume` (>24 h)         | warning             | 2026-05-10   |
| [Tailscale mesh MTU](tailscale-mesh-mtu.md)                          | symptom-driven (intermittent cross-node)         | warning             | 2026-05-10   |
| [Flux reconcile stalled](flux-reconcile-stalled.md)                  | `FluxKustomizationNotReady` (>10 m / >30 m)      | warning → critical  | 2026-05-10   |

## When this is the wrong directory

If the alert is for a workload running in **Tier-2** Compose (Plex, the
*arr stack, Vaultwarden, Nextcloud, Immich), this might still be the right
directory — but check whether the runbook lives next to the Compose file
in [`compose/<stack>/README.md`](../../compose/) first. The split is
deliberate: Tier-2 services own their own operational notes near the code.
Cross-tier infra (k3s, the network, backups) lives here.
