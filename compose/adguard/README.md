# AdGuard Home (future addition)

Recursive DNS resolver with ad/tracker filtering and split-horizon rewrites
for `loogi.ch` and `example.com` (so tailnet clients reach Tier-1/Tier-2
services on `100.64.0.0/10` instead of the public IP).

**Status — currently aspirational.** Today airbase forwards DNS directly to
upstream resolvers; this Compose file exists so AdGuard can be brought up
with `docker compose up -d` on whichever host gets nominated as the homelab
resolver, without any architectural rework.

The earlier doc note about AdGuard running as a Proxmox LXC is stale —
airbase is bare-metal Debian, see
[ADR 0010](../../docs/adr/0010-airbase-bare-metal-no-proxmox.md). When
AdGuard does come online it will run here as a Compose container in
`network_mode: host`.

- Future public domain: cluster-internal only (no public ingress for DNS UI)
- Upstream: <https://github.com/AdguardTeam/AdGuardHome>
