# n8n

Workflow automation engine plus its dedicated Postgres 16 backing store. Both
containers join `n8n_internal`; only `n8n_app` additionally joins `proxy-net`
so Nginx Proxy Manager can reach it as `n8n:5678`.

- Public domain: **n8n.psimaker.org**
- Upstream: <https://docs.n8n.io/hosting/>
- Telemetry, version-check, and template gallery are disabled — see env block.
