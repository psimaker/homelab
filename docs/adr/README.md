# Architecture Decision Records

An Architecture Decision Record (ADR) is a short document that captures a
single significant decision: what was decided, what forces drove it, and
what alternatives were rejected. ADRs are written at the moment of the
decision and are not edited later, except to mark them superseded by a
newer ADR. The point is to make the *judgment* behind the system legible
to a future reader (including future-me) without having to reconstruct it
from `git log` and folklore.

This repository uses a **MADR-light** format. Every ADR lives in this
directory as a single Markdown file, numbered sequentially. The canonical
narrative — the "what runs where, and why" — lives in
[`../architecture.md`](../architecture.md). Where that document needs to
explain a decision in depth, it links here.

## Index

| #    | Title                                                                       | Date       | Status   | Summary |
| ---- | --------------------------------------------------------------------------- | ---------- | -------- | ------- |
| 0001 | [Tier-1 / Tier-2 split](0001-tier1-tier2-split.md)                          | 2025-08-14 | Accepted | Kubernetes for new and stateless workloads; existing Compose stacks on `airbase` stay in place. |
| 0002 | [Flux over ArgoCD](0002-flux-vs-argocd.md)                                  | 2025-09-03 | Accepted | Flux v2 is the sole GitOps controller; no ArgoCD UI to tempt click-ops. |
| 0003 | [Renovate self-hosted, against Gitea](0003-renovate-self-hosted.md)         | 2025-09-21 | Accepted | Renovate runs in-cluster as a CronJob, opening PRs on the primary Gitea repository. |
| 0004 | [Secrets: SOPS+age over Vault](0004-secrets-sops-vs-vault.md)               | 2025-09-28 | Accepted | SOPS+age encrypts secrets in the public mirror; Vault is overkill for a single-operator homelab. |
| 0005 | [Two TLS issuers, deliberately](0005-tls-zwei-issuer.md)                    | 2025-10-12 | Accepted | cert-manager (DNS-01) for Tier-1, NPM's built-in ACME for Tier-2 — no migration tax for the existing setup. |
| 0006 | [Pocket-ID over Authentik](0006-pocket-id-vs-authentik.md)                  | 2026-01-08 | Accepted | One container plus SQLite for the OIDC provider; Authentik's footprint is disproportionate to the user count. |
| 0007 | [Backups: restic, 3-2-1, weekly tested restore](0007-backup-restic-3-2-1.md) | 2025-11-09 | Accepted | restic to Hetzner Storage Box plus Backblaze B2; restore tests run weekly in CI. |
| 0008 | [Cross-tier scraping over Tailscale](0008-cross-tier-scraping-tailscale.md) | 2026-01-22 | Accepted | Prometheus on Tier-1 scrapes `airbase` via the tailnet; no public scrape surface. |
| 0009 | [Internal-only observability](0009-internal-only-observability.md)          | 2026-02-04 | Accepted | No public Grafana, Beszel, or status page; everything is Tailscale-gated. |
| 0010 | [airbase stays bare-metal Debian, no Proxmox](0010-airbase-bare-metal-no-proxmox.md) | 2025-08-19 | Accepted | A working 50-container Docker host does not benefit from a hypervisor layer. |
| 0011 | [Cilium as the k3s CNI](0011-cilium-as-cni.md)                              | 2025-12-15 | Accepted | Cilium replaces Flannel for Hubble observability, NetworkPolicy enforcement, and Gateway API readiness. |
| 0012 | [Headscale over vanilla WireGuard](0012-headscale-vs-vanilla-wireguard.md)  | 2025-10-27 | Accepted | Self-hosted Headscale plus Tailscale clients: one identity domain, ACLs as code, no vendor dependency. |
| 0013 | [Gitea stays, Forgejo on the watchlist](0013-gitea-bleibt-forgejo-watchlist.md) | 2026-03-11 | Accepted | Keep the working Gitea; migrate to Forgejo only when there is a concrete trigger. |

## Adding a new ADR

1. Copy [`0000-template.md`](0000-template.md) to the next sequential
   number (`NNNN-short-kebab-title.md`).
2. Fill in the sections. Keep it to one decision; if it grows past the
   template's shape, it is probably two decisions.
3. Open a pull request. The discussion in the PR is part of the
   decision record; once merged, the ADR itself does not change.
4. Add a row to the table above.
5. If the new ADR supersedes an existing one, update the older ADR's
   **Status** field to `Superseded by ADR-NNNN` and link the new one in
   its **Notes** section. Do not delete the older ADR.

## Conventions

- **Voice:** first-person singular ("I"), to match the single-operator
  reality of this homelab.
- **Tense:** decisions are stated in the present tense, in the voice of
  someone who has already moved on to implementing them.
- **Length:** roughly 250–450 words. If an ADR is shorter, the
  alternatives section is probably underweight; if longer, the decision
  is probably two decisions.
- **Tags:** one to three lowercase tags per ADR, useful for grep.
- **Cross-links:** ADRs link each other when their reasoning depends on
  each other. ADR-0008 depends on ADR-0012; ADR-0001 is the foundation
  for almost everything else.
- **Status integrity:** an ADR's status field is the truth about whether
  the decision is current. If reality has diverged, write a new ADR
  that supersedes the old one rather than editing history.
