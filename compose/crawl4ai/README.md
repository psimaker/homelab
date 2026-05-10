# crawl4ai

Headless web-extraction service with LLM-driven structure inference. Reachable
inside `proxy-net` as `crawl4ai:11235`; consumed by LOOGI's SearXNG and by
internal n8n workflows. No public ingress.

- No public domain (cluster-internal only)
- Upstream: <https://docs.crawl4ai.com/core/docker-deployment/>
- Two env files: `.env` (tag + API token) and `.llm.env` (provider keys, loaded via `env_file:`).
