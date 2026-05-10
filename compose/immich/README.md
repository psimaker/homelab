# Immich

Self-hosted photo library: server + machine-learning + Postgres + Valkey. The
ML container extends the `cuda` service from `hwaccel.ml.yml` so face/object
recognition runs on the airbase NVIDIA GPU.

- Public domain: **photos.example.com**
- Upstream: <https://immich.app/docs/install/docker-compose>
- Photo originals live on `/mnt/hdd/photos`; Postgres on NVMe at `/data/immich/postgres`.
