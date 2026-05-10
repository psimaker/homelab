# `ansible/`

Configuration management for the two homelab nodes:

- **`edge`** — Hetzner CX22, k3s server, Cloudflare Tunnel daemon (host
  fallback), Tailscale joined to Headscale.
- **`airbase`** — home server, k3s agent + Docker host, restic timer,
  observability agents.

The split between Tier-1 (k3s, GitOps) and Tier-2 (Compose on airbase) is
explained in [`docs/architecture.md`](../docs/architecture.md). Ansible
manages the **host** layer; Compose stacks themselves live in
[`compose/`](../compose/), and Tier-1 workloads are reconciled by Flux from
[`kubernetes/`](../kubernetes/).

## Layout

```
ansible/
├── ansible.cfg
├── requirements.yml          collections + roles, pinned, Renovate-tracked
├── inventory/
│   ├── hosts.yml             two hosts, four groups
│   └── group_vars/
│       ├── all.yml           non-secret defaults
│       ├── all.sops.yml      SOPS-encrypted secrets (shape documented inside)
│       ├── home_dataplane.yml
│       └── edge.yml
├── playbooks/
│   ├── site.yml              the master playbook
│   ├── airbase.yml           subset — only home_dataplane
│   ├── edge.yml              subset — only edge
│   ├── k3s-bootstrap.yml     server-then-agent ordering
│   └── rotate-restic-keys.yml  rare maintenance
└── roles/
    ├── baseline              packages, sysctl, SSH hardening, fail2ban, UFW, node_exporter
    ├── docker_host           Docker CE + compose plugin from upstream apt
    ├── tailscale_node        Tailscale + Headscale enrolment
    ├── k3s_server            k3s control-plane on edge
    ├── k3s_agent             k3s worker on airbase
    ├── observability_agent   Promtail + Beszel agent
    ├── cloudflared_host      Cloudflare Tunnel daemon (edge fallback)
    └── restic_host_job       restic + systemd timer (3-2-1 backups)
```

Every role follows the standard Galaxy layout: `tasks/`, `handlers/`,
`defaults/`, `templates/`, `meta/`, `README.md`.

## Prerequisites

- **Ansible 10+** with the collections from `requirements.yml`. Install
  with:
  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```
- **`sops` 3.9+** with an age private key at
  `~/.config/sops/age/keys.txt` matching the `&admin` recipient in
  [`.sops.yaml`](../.sops.yaml). The `community.sops.sops` vars plugin
  decrypts inventory secrets transparently at runtime.
- **SSH access to both hosts** as the operator user (`umo`) with a
  pubkey listed in `operator_ssh_keys`. The very first run against
  edge uses the key Hetzner cloud-init injects.
- **Hosts**:
  - `airbase` reachable on the LAN at `192.168.8.112`.
  - `edge` reachable on its public IPv4 the first time, on
    `edge.tailnet` afterwards.

## Common commands

```bash
# Full apply — both hosts, every role.
ansible-playbook playbooks/site.yml

# Dry-run with a diff.
ansible-playbook playbooks/site.yml --check --diff

# Apply only one role across the inventory.
ansible-playbook playbooks/site.yml --tags docker_host

# Apply only to one group.
ansible-playbook playbooks/edge.yml
ansible-playbook playbooks/airbase.yml

# First-ever bootstrap of a fresh edge node — Tailscale not yet enrolled.
ansible-playbook playbooks/site.yml \
  -e ansible_host=<hetzner-ipv4> \
  --skip-tags tailscale

# k3s install only (server then agent).
ansible-playbook playbooks/k3s-bootstrap.yml
```

## Bootstrap order

The very first run from a clean Hetzner project follows
[`docs/architecture.md` § Bootstrap sequence](../docs/architecture.md#bootstrap-sequence).
The Ansible-relevant bits:

1. OpenTofu has provisioned the Hetzner CX22; cloud-init has injected the
   operator pubkey.
2. Run `ansible-playbook playbooks/edge.yml --skip-tags tailscale,k3s` to
   get baseline hardening, observability agents, and cloudflared in place.
3. Run `ansible-playbook playbooks/edge.yml --tags k3s_server` to bring
   the cluster up.
4. Bootstrap Flux on edge (out of scope for Ansible).
5. Wait for Headscale to be reconciled by Flux.
6. Generate a Headscale pre-auth key, add it to the SOPS inventory file,
   re-encrypt, then run `ansible-playbook playbooks/site.yml` — this time
   with no `--skip-tags`, the Tailscale role enrols both nodes and the
   k3s agent on airbase joins via the tailnet.

The chicken-and-egg between Headscale and Tailscale is documented in
[`roles/tailscale_node/README.md`](roles/tailscale_node/README.md).

## Idempotency

Every role is written so a second run is a no-op:

- Versioned downloads (k3s, restic, promtail, node_exporter, beszel,
  helm, flux) check the installed version before fetching.
- All systemd units use `daemon_reload: true` and `state: started` —
  they only restart when handlers fire on a config change.
- Repository init for restic checks `restic cat config` before running
  `restic init`.
- `tailscale up` only runs when `tailscale status --json` shows
  `BackendState != Running`.

## Linting

Locally:

```bash
ansible-lint --profile production
yamllint .
```

In CI: [`.gitea/workflows/ansible-check.yml`](../.gitea/workflows/) runs
both on every PR touching `ansible/`, plus `ansible-playbook --check
--diff` against the live tailnet using a read-only SSH key.

## Secrets

All secrets are SOPS-encrypted in
[`inventory/group_vars/all.sops.yml`](inventory/group_vars/all.sops.yml).
The committed file in the public mirror has every value replaced with
`ENC[AES256_GCM,...]` ciphertext under a `sops:` metadata block; only the
shape is human-readable. Decryption requires an age private key matching
one of the recipients in [`.sops.yaml`](../.sops.yaml).

To rotate a single value:

```bash
sops inventory/group_vars/all.sops.yml   # opens an editor on plaintext
```

To rotate the age recipient set:

```bash
sops updatekeys inventory/group_vars/all.sops.yml
```

The `community.sops.sops` vars plugin in [`ansible.cfg`](ansible.cfg)
makes Ansible decrypt the file on the fly during a playbook run; there
is no persistent plaintext on disk.

## Adding a new role

```bash
ansible-galaxy role init roles/<name>
```

Conventions enforced by review:

- `defaults/main.yml` for every overridable value.
- Tasks use `ansible.builtin.*` FQCNs. No bare `command:` / `shell:`
  unless there is no module that does the job.
- `become: true` / `become: false` is explicit on every play and task
  block, never inherited silently.
- The role applies its own name as a tag so it can be targeted.
- A `README.md` documenting variables, tags, and the *why*.

## See also

- [`docs/architecture.md`](../docs/architecture.md) — the design brief.
- [`docs/adr/`](../docs/adr/) — the *why* behind individual decisions.
- [`scripts/bootstrap.sh`](../scripts/bootstrap.sh) — the wrapper that
  runs OpenTofu, then this Ansible, then Flux bootstrap.
