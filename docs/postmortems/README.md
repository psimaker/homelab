# Postmortems

This directory holds the postmortems for incidents in this homelab.

## What postmortems are for here

I write postmortems for the same reason a small team in a real ops org
would: **not to assign blame, but to extract every drop of learning** from
a thing that went wrong, and to leave a trail that future-me (or anyone
reading the repo) can use to understand why the system is shaped the way
it is.

The conventions:

- **Blameless.** There is one operator (me). Pretending otherwise would
  be silly. But the postmortem voice is still about *systems and
  decisions*, not *I-was-stupid-here*. The point is what changed in my
  model of the system, not flagellation.
- **Lessons-focused.** Every postmortem ends with at least one
  paragraph of *what I now believe is true that I didn't before*. If
  the incident didn't change my mental model, it doesn't deserve a
  postmortem — a runbook update or an issue is enough.
- **Action-oriented.** Action items are checkbox lists with owner, due
  date, and link to the tracking issue. I keep them in the postmortem
  even after they're closed (with the box checked) so the document
  remains a snapshot of "what we did about this".

## When I write one

A postmortem is mandatory when:

- A user-facing service was degraded for >5 minutes (LOOGI, Nextcloud,
  Vaultwarden, Immich, Paperless, Gitea, Headscale).
- An incident took >30 minutes to fix from detection.
- Anything touched encryption, secrets, or backup integrity.
- A backup or restore failure occurred (no minimum duration — backup
  failures get the strict treatment because they're silent failures by
  default).
- Two or more independent runbooks fired in the same window (composite
  failure deserves its own analysis).

A postmortem is *optional but encouraged* when:

- An alert fired, the runbook said "this is a known cause, do the
  obvious thing", and that worked. (Usually no, unless the same one
  fires three times.)
- A change I shipped required immediate rollback. (Yes if the change had
  passed CI; no if I caught it locally.)

## Structure

Every postmortem follows [`_template.md`](_template.md) — At a glance,
Timeline, Summary, Impact, Root cause, What went well, What went wrong,
What we got lucky on, Action items, Lessons. The "what we got lucky on"
section is the most underrated of the seven: making luck explicit reveals
hidden fragilities.

## Index

| Date       | Severity | Summary                                                                              | Action items |
| ---------- | -------- | ------------------------------------------------------------------------------------ | ------------ |
| 2026-02-11 | major    | [restic prune hit Storage Box quota mid-flight, nightly backup failed](2026-02-11-restic-prune-took-out-storagebox-quota.md) | 6 / 8 done |
| 2025-09-23 | major    | [LOOGI Cloudflare Tunnel flapped for ~2h, p95 spiked, SLO budget burned ~30 %](2025-09-23-loogi-tunnel-flap.md) | 5 / 6 done |

(Sorted by date descending — newest first.)
