# ADR-0013 — Gitea stays, Forgejo on the watchlist

- **Status:** Accepted
- **Date:** 2026-03-11
- **Tags:** git, forge

## Context

The primary forge for this homelab is **Gitea**, hosted at
`git.example.com`. It has been running for years, holds the source
of truth for this repository (and many others), runs the Gitea
Actions runner that drives every CI workflow in `.gitea/workflows/`,
and is integrated into Renovate (ADR-0003), Flux's bootstrap, and the
mirroring pipeline that publishes the GitHub copy.

The Forgejo fork was an actually-meaningful divergence; by 2026 it
has matured into a credible standalone project with its own release
cadence, a more federation-friendly direction, and noticeably more
community momentum than Gitea on the contributor side. A migration
path exists (Forgejo started life as a soft fork) and is well-trodden.
The friends-and-acquaintances impression I have from operators I
trust is mixed: some are happy to have moved, some have hit edge
cases, none describe migration as trivial.

## Decision

I am **keeping Gitea** and putting **Forgejo on the watchlist**. No
migration is planned today. The trigger for migrating, when it
comes, will be one of: a security issue or breaking change in Gitea
that Forgejo has already fixed; a feature on the Forgejo side that I
genuinely need (federation comes to mind); or a clear signal that
Gitea upstream is no longer keeping up with self-host operator
needs. "The community has moved" is itself not yet a sufficient
trigger — I need a concrete "this thing is broken / missing in
Gitea" before paying the migration cost.

## Consequences

### Positive

- Zero work today. The forge that runs the entire CI surface keeps
  running.
- The decision is documented as a deliberate hold, not as inertia. I
  know I am choosing not to migrate, and I know what would change my
  mind.
- Gitea's API and webhooks (used by Renovate, Flux, and the mirroring
  workflow) keep working without re-validation against a fork.

### Negative

- I am accepting some technical debt in the form of "this might be
  the wrong fork in 18 months". Mitigated by reviewing this ADR
  annually as part of Q1 housekeeping.
- If a CVE drops on Gitea and Forgejo has already fixed it, the
  migration becomes urgent rather than scheduled. Acceptable risk;
  I follow both projects' release notes.

### Neutral / known unknowns

- Renovate's auto-merge config may need adjustment if I migrate, since
  Forgejo's API surface is mostly compatible but not identical. The
  effort is bounded; the risk is low.

## Alternatives considered

### Option A — Migrate to Forgejo immediately

Lots of operators have, the tooling exists, the migration is the
straightforward kind. Rejected because there is no concrete payoff
today: the things Forgejo does better are things I do not currently
need (federation, a different governance story, slightly nicer UI in
places), and the migration cost is non-zero.

### Option B — Migrate to GitHub Enterprise / GitHub Team

Hosted, polished, well-integrated. Rejected because the public
GitHub mirror already exists for the recruiter-facing artefact, and
moving the primary off self-hosted infrastructure undoes the
sovereignty argument that justified self-hosting Gitea in the first
place.

### Option C — Self-host GitLab

Heavier, more featureful, more committed to a particular workflow.
Rejected because GitLab's resource footprint is wildly disproportionate
to the workload (one human, a handful of repos), and because nothing
about the current setup is suffering from "Gitea is too small".

## Notes

Linked from `architecture.md` ("Things deliberately not done").
Reviewed annually during Q1 housekeeping; the trigger conditions
above are the things to watch for.
