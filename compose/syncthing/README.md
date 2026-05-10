# Syncthing + vaultsync-notify

Two containers. `syncthing` is upstream Syncthing exposing port 22000 (sync)
and 21027 (discovery) on the host. `vaultsync-notify` is a small companion
that polls the Syncthing API, debounces FolderCompletion events for the
encrypted vault folder, and forwards them to the VaultSync iOS app via a
public relay so the phone wakes up when the desktop edits a vault.

- Public domain: **syncthing.example.com** (WebUI only, via NPM)
- Upstream: <https://docs.syncthing.net/> and <https://github.com/psimaker/vaultsync-notify>
- Sync ports are exposed directly on the host; only the WebUI goes through NPM.
