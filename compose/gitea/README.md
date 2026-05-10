# Gitea

Self-hosted Git server with built-in Actions support. Pairs with
[`gitea-runner/`](../gitea-runner/) for CI. Postgres backing store lives in a
dedicated `gitea-net` bridge that the runner also joins; `:3000` is bound to
`127.0.0.1` so only NPM exposes the HTTP UI, while `:2222` is host-published
for SSH clone/push.

- Public domain: **git.psimaker.org**, SSH on `:2222`
- Upstream: <https://docs.gitea.com/installation/install-with-docker>
- Open registration is off; signed-in view is required.
