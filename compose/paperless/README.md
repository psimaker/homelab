# Paperless-ngx

Document archive with Postgres + Redis backing. Tika and Gotenberg sit behind
the optional `optional-doc-conversion` profile (Office formats); paperless-gpt
behind the `ai` profile auto-tags newly consumed documents via DeepSeek.

- Public domain: **docs.example.com**
- Upstream: <https://docs.paperless-ngx.com/>
- Bring up everything: `docker compose --profile optional-doc-conversion --profile ai up -d`
