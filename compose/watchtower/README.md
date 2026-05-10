# Watchtower

Single-container image updater. Runs a cron at 04:00 every 3 days, pulls fresh
tags for opted-in containers, restarts them sequentially (rolling restart is
explicitly disabled — for one host, sequential is safer), and posts a digest
to ntfy. Containers without the `com.centurylinklabs.watchtower.enable=true`
label are ignored.

- No public domain (no UI)
- Upstream: <https://github.com/nicholas-fedor/watchtower>
- Failures leave the running container in place; nothing is deleted until a new image is verified pullable.
