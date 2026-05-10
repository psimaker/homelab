# Nextcloud AIO

The "master container" for Nextcloud All-in-One. AIO is largely
self-bootstrapping: this single container reads the host Docker socket and
spawns/manages all other Nextcloud services (apache, database, redis, talk,
imaginary, fulltextsearch) via the AIO web UI on `:8080`.

- Public domain: **nextcloud.psimaker.org** (Apache exposed inside `proxy-net`
  on port 11000)
- Upstream: <https://github.com/nextcloud/all-in-one>
- AIO admin UI: `http://airbase:8080` — first-run wizard prints a one-time setup password.
