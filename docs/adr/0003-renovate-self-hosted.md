# ADR-0003 — Renovate self-hosted, against Gitea

- **Status:** Accepted
- **Date:** 2025-09-21
- **Tags:** gitops, dependencies, ci

## Context

The primary repository for this homelab is on a self-hosted Gitea
(`git.psimaker.org`). GitHub is a read-only mirror, force-pushed from
CI on every push to main. Pull requests, code review, and CI all happen
on Gitea. That is a deliberate choice (sovereignty, data residency, the
mirror is a recruiter-facing artefact). It does, however, rule out the
hosted GitHub-app version of Renovate, which is the path of least
resistance for most projects.

I want Renovate to open pull requests for Helm chart versions, container
images (including digest pins for SearXNG, see `architecture.md`), Flux
manifests, OpenTofu providers, and Ansible Galaxy roles. The PR has to
land on Gitea, where my CI runs, not on a mirror where it would be a
dead-end. And Renovate has to authenticate to Gitea, not to GitHub.

## Decision

I run Renovate **self-hosted, in-cluster**, as a Kubernetes `CronJob` in
the `renovate` namespace on Tier-1. It runs on a fixed schedule
(`before 6am on monday` and `before 6am on thursday`, Europe/Zurich),
authenticates to Gitea with a service-account token, and opens pull
requests against the primary `git.psimaker.org/umut.erdem/homelab`
repository. The Renovate image is itself Renovate-tracked (currently
`ghcr.io/renovatebot/renovate:38`).

## Consequences

### Positive

- The dependency-update loop closes against the primary repository, not
  a mirror.
- No external SaaS in the critical path of the homelab's update
  workflow.
- Schedule, platform, host rules, and package rules are all in
  `renovate.json5`, which is itself reviewed and versioned.
- Auto-merge policy can be tuned per ecosystem (Flux/Cilium/Traefik
  patches auto-merge; k3s and Cloudflare provider bumps are gated).

### Negative

- I am responsible for keeping the Renovate image current and the
  CronJob healthy. When Renovate stops opening PRs, I have to notice.
- Schedule-based runs mean updates land in batches rather than as
  upstream releases drop — usually fine, occasionally annoying.
- Initial configuration of the Gitea platform plus the Renovate
  cache + token rotation is more setup than `mend.io` would have been.

### Neutral / known unknowns

- Renovate's Gitea support has improved a lot but is still a second-tier
  platform compared to its GitHub support. I expect to hit edge cases
  occasionally and contribute fixes upstream when I do.

## Alternatives considered

### Option A — Mend.io hosted Renovate

Free for open-source, low-friction, well-maintained. Rejected because
the primary is Gitea: Mend's Gitea integration exists but is not the
hot path of their product, and putting an external SaaS in the loop
defeats the point of self-hosting Gitea in the first place.

### Option B — GitHub Dependabot

Mature, free, well-integrated. Rejected because Dependabot only opens
PRs on GitHub, and the GitHub repository here is a force-pushed mirror —
PRs against it would be overwritten on the next mirror push.

## Notes

`renovate.json5` lives at the repository root. Tuning the auto-merge
list is the file most likely to change as I gain or lose trust in
specific ecosystems. Linked from ADR-0002.
