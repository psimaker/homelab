# Runbook — <Alert / Issue Name>

> **Triggers:** which Prometheus alert fires, or what symptom you're chasing
> **Severity:** critical | warning | info
> **Audience:** on-call (just me), but written so a future-me at 2 AM can follow

## TL;DR (60-second triage)

1. First thing to check
2. Second
3. Third
4. If still red, escalate to "Investigate" below

## Context

Why this matters. What's affected when this fires.

## Investigate

Step-by-step commands the operator runs. Use real `kubectl`, `flux`, `talosctl`,
`journalctl`, `restic`, `loki` queries. Show the actual command + the expected
output.

## Common causes

Bulleted list of the most likely root causes, ordered by frequency.

## Mitigation

What to do once you've identified the cause. Include the "if I just want it to
stop paging" emergency mitigation, and the "fix it properly" path.

## Postmortem requirement

If this fires and the fix takes >30 min OR causes user-facing impact >5 min,
open a postmortem in `docs/postmortems/`.

## Related

- Architecture: link to relevant `docs/architecture.md` section
- ADRs: links to relevant ADRs
- Past postmortems: links to past incidents that hit this runbook
