# xbrowsersync

Self-hosted xbrowsersync API + Mongo 4.4 backing store. The browser extension
encrypts bookmarks client-side before uploading, so the server only stores
opaque blobs — no admin can read user data.

- Public domain: **bookmarks.example.com**
- Upstream: <https://github.com/xbrowsersync/api>
- The API container needs `settings.json`, `healthcheck.js`, and `mongoconfig.js`
  bind-mounted from the host (kept on airbase under `/data/xbrowsersync/`).
