#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# sops-encrypt.sh — encrypt a plaintext file in place, picking the right
# encryption pattern based on the file path and .sops.yaml creation rules.
#
# This is a thin wrapper around `sops --encrypt --in-place`. The reason it
# exists: SOPS reads `creation_rules` automatically when you encrypt a file
# whose path matches a rule, but only if you cd to the repo root and use a
# RELATIVE path. This wrapper does that bookkeeping for you so the call site
# can pass an absolute path and not think about cwd.
#
# Usage:
#   ./scripts/sops-encrypt.sh kubernetes/apps/loogi/secret.sops.yaml
#   ./scripts/sops-encrypt.sh /abs/path/to/terraform/live/prod/terraform.tfvars.sops.json
#   ./scripts/sops-encrypt.sh --help
#
# Prerequisites:
#   - .sops.yaml present at repo root with rules that cover the target path
#   - SOPS_AGE_KEY_FILE or ~/.config/sops/age/keys.txt available
#
# Notes:
#   - The file MUST already exist as plaintext. We don't write content.
#   - If the file path doesn't match any rule, sops will error; we surface it.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_RESET=""
fi
log_info() { printf '%s[INFO]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
log_ok()   { printf '%s[OK]%s   %s\n' "${C_GREEN}"  "${C_RESET}" "$*"; }
log_fail() { printf '%s[FAIL]%s %s\n' "${C_RED}"    "${C_RESET}" "$*" >&2; }
die()      { log_fail "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 <plaintext-file>

Encrypt a file in place using the .sops.yaml rule that matches its path.

Options:
  -h, --help    Show this help.
EOF
}

# ---- args ------------------------------------------------------------------
if [[ $# -ne 1 ]] || [[ "$1" =~ ^(-h|--help)$ ]]; then
  usage
  [[ "${1:-}" =~ ^(-h|--help)$ ]] && exit 0
  exit 64
fi

target="$1"

# ---- normalise path: must be inside repo root ------------------------------
abs_target="$(cd "$(dirname "${target}")" 2>/dev/null && pwd)/$(basename "${target}")" \
  || die "Cannot resolve ${target}"

case "${abs_target}" in
  "${REPO_ROOT}"/*) ;;
  *) die "${target} is not inside ${REPO_ROOT}." ;;
esac
rel_target="${abs_target#"${REPO_ROOT}/"}"

[[ -f "${abs_target}" ]] || die "Not a file: ${abs_target}"

# ---- naming sanity --------------------------------------------------------
if [[ "${rel_target}" != *".sops."* ]]; then
  log_fail "Filename does not contain '.sops.' segment: ${rel_target}"
  log_fail "Convention: <name>.sops.<ext>  (e.g. secret.sops.yaml, terraform.tfvars.sops.json)"
  exit 1
fi

# ---- already encrypted? ----------------------------------------------------
if grep -q '^sops:' "${abs_target}" 2>/dev/null \
    || grep -q '"sops"[[:space:]]*:' "${abs_target}" 2>/dev/null; then
  log_fail "${rel_target} appears to be already encrypted (has 'sops:' marker)."
  log_fail "Use ./scripts/sops-decrypt.sh to inspect, or sops --rotate to re-key."
  exit 1
fi

# ---- run sops from repo root so .sops.yaml rules apply ---------------------
log_info "Encrypting (in place): ${rel_target}"
( cd "${REPO_ROOT}" && sops --encrypt --in-place "${rel_target}" )
log_ok  "Encrypted: ${rel_target}"
