# ADR-0004 — Secrets: SOPS+age over Vault

- **Status:** Accepted
- **Date:** 2025-09-28
- **Tags:** secrets, security

## Context

The homelab has roughly thirty secrets that need to live somewhere:
Cloudflare API tokens, Hetzner credentials, an OIDC client secret per
service, restic repository passwords, a Gitea runner registration
token, and so on. These are accessed by exactly one human operator
(me), one Kubernetes cluster, and a small set of CI runners. The
audit requirement is "I want to be able to answer 'when did this
secret last change and why' six months from now".

The shape of "production-grade secret management" most reference
architectures point at is HashiCorp Vault, with dynamic secrets, a
PKI engine, leases, identity tokens, and ideally an HSM. That is the
right tool for an organisation with humans who have heterogeneous
access requirements. It is the wrong tool for one human, one cluster,
and a daily-driver laptop where the threat model is "I lose the
laptop" and "I push the wrong file to a public repo".

## Decision

I am using **SOPS + age**. Encrypted secret files live in the
repository (including the public mirror); the age private key lives in
exactly three places: my laptop's `~/.config/sops/age/keys.txt`, a
`Secret/sops-age` resource in the `flux-system` namespace, and a
`SOPS_AGE_KEY` CI runner secret. Recipients are pinned in `.sops.yaml`.
Every secret change is a commit, and the audit trail is `git log`.

External-Secrets Operator is installed but used sparingly — only when
a secret genuinely needs an external source of truth (currently: the
Cloudflare API token sourced from a 1Password vault). That preserves a
defensible upgrade path if the threat model changes.

## Consequences

### Positive

- One mechanism, one mental model. Decryption happens in three places
  and the configuration for all three lives in one file.
- The audit trail is `git log`, which I already read.
- Public mirror is safe: commits land encrypted, and CI checks block
  any plaintext from being pushed.
- Key rotation is rehearsed: a script in `scripts/rotate-age-key.sh`
  walks through `sops updatekeys`, the cluster Secret, and CI.

### Negative

- Single age key compromise = total compromise. Mitigated by storing
  the key only on devices I control and rotating annually as part of
  Q1 housekeeping.
- No dynamic secrets. If a service supports rotating credentials, I
  rotate them by editing the SOPS file, not by issuing a lease.
- Adding a future operator means re-encrypting every file with their
  recipient added. Acceptable for n=1, painful at n=5.

### Neutral / known unknowns

- If I ever need PKI-as-a-service or short-lived database credentials,
  I will revisit. External-Secrets is the seam I would extend through.

## Alternatives considered

### Option A — HashiCorp Vault

The right answer for an organisation. Rejected here because the
operational cost (one more stateful service, unsealing on restart,
ACL policy management) is paid every day, while the benefit
(dynamic secrets, leases, multi-operator policy) is not exercised at
all in a single-operator homelab.

### Option B — Sealed-Secrets

Lower operational overhead than Vault, k8s-native. Rejected because
its key-rotation story is poor — re-encrypting all sealed secrets when
the controller key rotates is awkward — and because it is k8s-only,
which leaves Tier-2 and Ansible without a story.

### Option C — Bitwarden Secrets Manager

A reasonable hosted option. Rejected because it adds vendor lock-in
to a service I would then need to keep paying for or migrate off of.

## Notes

Linked from `architecture.md` in the secrets section. Revisit when:
a second operator joins; when a service's threat model demands
short-lived credentials; or when SOPS upstream goes unmaintained.
