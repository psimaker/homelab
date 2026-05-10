# .github/workflows — mirror only, no real CI

This directory exists because the public mirror is on **GitHub**, but the
canonical repository — and the only CI that matters — lives on **Gitea**:

> https://git.psimaker.org/umut.erdem/homelab → `.gitea/workflows/`

The workflows in this directory are intentional no-ops:

- [`lint.yml`](lint.yml) — runs `yamllint` only. It does not gate anything,
  it does not assert manifest validity, it does not check secret encryption.
  It exists so the GitHub Actions tab is not empty when somebody arrives via
  a recruiter link.
- [`mirror-status.yml`](mirror-status.yml) — single-step workflow that posts
  a pointer back to Gitea so anybody opening the Actions tab knows where
  the real CI lives.

## Why?

Two reasons:

1. **Source of truth.** Pushing to GitHub triggers a no-op; pushing to Gitea
   triggers the real lint/test/apply pipelines and *then* mirrors the result
   to GitHub via [`mirror-github.yml`](../../.gitea/workflows/mirror-github.yml).
   Adding real CI here would create a second source of truth and a chance
   for the two to drift.
2. **Secret minimisation.** The Gitea runner has `SOPS_AGE_KEY`, the SSH
   private key for airbase + edge, restic credentials, ntfy tokens, GitHub
   PAT, B2 keys. None of those should be replicated into a GitHub
   organisation secret store — fewer copies, smaller blast radius.

## Don't add real CI here

If you want a check to run on every PR, add it to
[`.gitea/workflows/lint.yml`](../../.gitea/workflows/lint.yml). The mirror
will reflect the result; nothing has to live in this directory.
