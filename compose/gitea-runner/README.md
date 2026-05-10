# Gitea runner

Self-hosted `act_runner` for Gitea Actions. Joins the `gitea-net` network
created by the [`gitea/`](../gitea/) stack so it can reach the server by
container name. Uses the host Docker socket to launch job containers; the
`catthehacker/ubuntu:act-*` images give jobs an `ubuntu-latest`-compatible
environment.

- No public domain (jobs run in the runner; logs surface in Gitea UI)
- Upstream: <https://docs.gitea.com/usage/actions/act-runner>
- Cache toolchain artefacts in the named `gitea-runner-toolcache` volume.
