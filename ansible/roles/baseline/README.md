# `baseline`

Brings a freshly imaged Debian 12 host to the lowest configuration the rest
of the homelab assumes. Idempotent — running twice is a no-op.

## What it does

- Sets the hostname from `inventory_hostname` and aligns `/etc/hosts`.
- Sets the timezone (`timezone` var, default `Europe/Zurich`) and generates
  the locale (`locale`, default `en_US.UTF-8`).
- Installs the package set listed in `baseline_packages`. `qemu-guest-agent`
  is added on virtualised hosts only.
- Creates the operator user (`operator_user`), authorises the keys in
  `operator_ssh_keys`, grants passwordless sudo via a drop-in.
- Applies sysctl tuning relevant to a Docker + k3s host (forwarding, bridge
  netfilter, inotify watch limit) into `/etc/sysctl.d/99-homelab.conf`.
- Drops a hardening file into `/etc/ssh/sshd_config.d/99-homelab-hardening.conf`
  (validated with `sshd -t` before sshd is restarted) — root login off,
  password auth off, `MaxAuthTries 3`, `LoginGraceTime 20`.
- Configures `unattended-upgrades` for security-only updates without random
  reboots.
- Enables `fail2ban` with the `sshd` jail using the systemd backend.
- Enables `ufw` with default-deny inbound, allowing port 22/tcp and the
  Tailscale UDP port.

## Variables

See [`defaults/main.yml`](defaults/main.yml) for the full list. The most
common overrides:

| Variable | Default | Notes |
| --- | --- | --- |
| `operator_ssh_keys` | placeholder | List of authorised public keys. |
| `baseline_sysctl` | dict | Merge-friendly. Add a key, don't redefine. |
| `baseline_unattended_upgrades_auto_reboot` | `false` | Set `true` only on truly stateless nodes. |
| `baseline_ufw_rules` | `[22/tcp, 41641/udp]` | Add stack-specific ports here. |

## Tags

`baseline` — applies this role.

## Why these specific tunings

`net.bridge.bridge-nf-call-iptables=1` is required for kube-proxy and Docker
bridge networking to interact with iptables rules. `fs.inotify.max_user_watches`
must be high or both Promtail and any IDE-on-tailnet will see file-watch
exhaustion.
