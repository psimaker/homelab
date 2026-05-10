# arr-stack — media automation behind Gluetun

Twelve containers in one Compose file: a Gluetun WireGuard tunnel plus the
classic *arr suite (Radarr, Sonarr, Prowlarr, Bazarr), SABnzbd, FlareSolverr,
Umlautadaptarr, Configarr, Tdarr (out-of-tunnel for GPU transcode), Seerr (the
post-Feb-2026 Jellyseerr/Overseerr merge), and Maintainerr.

- Reachable on LAN + Tailscale only — no public ingress
- Source path on airbase: `/data/rr/` (kept the historic name; the public
  directory is `arr-stack/` for clarity)
- All indexer/download traffic is forced through Gluetun's WireGuard tunnel
  via `network_mode: service:gluetun`; if the tunnel drops, the kill-switch
  blocks everything until it recovers.
