# Arcane

Single-container Docker management UI. Mounts the host Docker socket so it can
list/manage every container on airbase, and `/data` so it can preview Compose
files in place. Locked to `127.0.0.1:3552` on the host — public access only
through Nginx Proxy Manager with auth in front.

- Public domain: **arcane.psimaker.org**
- Upstream: <https://github.com/getarcaneapp/arcane>
- High-privilege container — anyone with auth can stop/start every stack.
