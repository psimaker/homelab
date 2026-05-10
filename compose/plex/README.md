# Plex

Single-container Plex Media Server in `network_mode: host` (Plex's auto-discovery
protocols want raw broadcast). NVIDIA GPU passed through for hardware-accelerated
transcoding; `/dev/shm` mounted as the transcode scratch dir to keep writes off
the SSD.

- Reachable on LAN + Tailscale only (no public ingress)
- Upstream: <https://github.com/linuxserver/docker-plex>
- Media at `/mnt/hdd/media`, custom imported assets at `/mnt/hdd/custom` (read-only).
