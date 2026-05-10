# ntfy

Single-container push-notification server. Used by Watchtower for image-update
digests, by Alertmanager for `homelab-critical` and `homelab-warnings` topics,
and by an APT post-invoke hook on airbase that posts when packages get
upgraded.

- Public domain: **ntfy.psimaker.org**
- Upstream: <https://docs.ntfy.sh/install/>
- Topics are private by default (`NTFY_AUTH_DEFAULT_ACCESS=deny-all`); manage with `docker exec ntfy ntfy user add ...`.
