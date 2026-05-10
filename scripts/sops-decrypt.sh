#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# sops-decrypt.sh — decrypt a SOPS-encrypted file to stdout.
#
# Deliberately does NOT write to disk: the .gitignore covers `*.dec.*` to
# prevent leaks, but the only sure way is not to materialise plaintext at
# all. Pipe the output where you need it:
#
#   ./scripts/sops-decrypt.sh ansible/inventory/group_vars/all.sops.yml | less
#   ./scripts/sops-decrypt.sh kubernetes/apps/loogi/secret.sops.yaml \
#       | yq '.stringData.SEARXNG_SECRET_KEY'
#
# Usage:
#   ./scripts/sops-decrypt.sh <encrypted-file>
#   ./scripts/sops-decrypt.sh --help
#
# Prerequisites:
#   - sops on PATH
#   - SOPS_AGE_KEY_FILE or ~/.config/sops/age/keys.txt available
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -t 2 ]]; then
  C_RED=$'\033[31m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_RESET=""
fi
die() { printf '%s[FAIL]%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 <encrypted-file>

Decrypt a SOPS file and write its plaintext to stdout. Never writes to disk.

Options:
  -h, --help    Show this help.
EOF
}

if [[ $# -ne 1 ]] || [[ "$1" =~ ^(-h|--help)$ ]]; then
  usage
  [[ "${1:-}" =~ ^(-h|--help)$ ]] && exit 0
  exit 64
fi

target="$1"
abs_target="$(cd "$(dirname "${target}")" 2>/dev/null && pwd)/$(basename "${target}")" \
  || die "Cannot resolve ${target}"

case "${abs_target}" in
  "${REPO_ROOT}"/*) ;;
  *) die "${target} is not inside ${REPO_ROOT}." ;;
esac

[[ -f "${abs_target}" ]] || die "Not a file: ${abs_target}"

# Sanity: encrypted files have a sops:/sops" stanza.
if ! grep -q '^sops:' "${abs_target}" 2>/dev/null \
    && ! grep -q '"sops"[[:space:]]*:' "${abs_target}" 2>/dev/null; then
  die "${target} does not look SOPS-encrypted (no 'sops:' marker found)."
fi

# Decrypt purely to stdout — sops auto-detects the file format.
( cd "${REPO_ROOT}" && sops --decrypt "${abs_target#"${REPO_ROOT}/"}" )
