#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap-secrets.sh — one-time setup for SOPS+age.
#
# Generates an age keypair on the operator workstation, prints the public key,
# and walks you through the steps to wire it into .sops.yaml. The cluster
# recipient is regenerated separately (it lives in a Kubernetes Secret created
# by bootstrap.sh after k3s is up).
#
# This script is idempotent in the sense that it refuses to overwrite an
# existing key without confirmation. Run it exactly once per operator machine.
#
# Usage:
#   ./scripts/bootstrap-secrets.sh
#   ./scripts/bootstrap-secrets.sh --unattended    # auto-keep existing key
#   ./scripts/bootstrap-secrets.sh --help
#
# Prerequisites:
#   - age, age-keygen, sops on PATH
#
# Architecture: docs/architecture.md, section "Secrets"
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGE_KEY_FILE="${AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"
AGE_KEY_DIR="$(dirname "${AGE_KEY_FILE}")"

UNATTENDED=0

# ---- colours ---------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi
log_info() { printf '%s[INFO]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
log_ok()   { printf '%s[OK]%s   %s\n' "${C_GREEN}"  "${C_RESET}" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
log_fail() { printf '%s[FAIL]%s %s\n' "${C_RED}"    "${C_RESET}" "$*" >&2; }
log_step() { printf '\n%s%s== %s ==%s\n' "${C_BOLD}" "${C_BLUE}" "$*" "${C_RESET}"; }
die()      { log_fail "$*"; exit 1; }

confirm() {
  local prompt="${1:-Continue?}"
  if (( UNATTENDED == 1 )); then return 0; fi
  read -r -p "${C_BOLD}${prompt}${C_RESET} [y/N] " reply
  [[ "${reply}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

usage() {
  cat <<EOF
Usage: $0 [--unattended] [--help]

Generates an age keypair for SOPS at ${AGE_KEY_FILE} and prints the next steps.

Options:
  --unattended    Keep existing keys without prompting; never overwrite.
  -h, --help      Show this help.
EOF
}

# ---- args ------------------------------------------------------------------
while (( $# > 0 )); do
  case "$1" in
    --unattended) UNATTENDED=1 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

# ---- main ------------------------------------------------------------------
main() {
  log_step "Pre-flight"
  command -v age-keygen >/dev/null || die "age-keygen not found on PATH."
  command -v sops       >/dev/null || die "sops not found on PATH."
  log_ok "Tools present."

  log_step "Step 1/5  Generate age keypair"
  mkdir -p "${AGE_KEY_DIR}"
  chmod 700 "${AGE_KEY_DIR}"

  if [[ -f "${AGE_KEY_FILE}" ]]; then
    log_warn "${AGE_KEY_FILE} already exists."
    if (( UNATTENDED == 1 )); then
      log_info "Unattended mode — keeping existing key, exiting cleanly."
      exit 0
    fi
    if ! confirm "Overwrite (this can lock you out of existing encrypted files)?"; then
      log_info "Keeping existing key. Nothing changed."
      exit 0
    fi
    local backup="${AGE_KEY_FILE}.backup-$(date -u +%Y%m%dT%H%M%SZ)"
    cp -p "${AGE_KEY_FILE}" "${backup}"
    log_warn "Existing key backed up to ${backup}"
  fi

  age-keygen -o "${AGE_KEY_FILE}"
  chmod 600 "${AGE_KEY_FILE}"
  log_ok "Wrote ${AGE_KEY_FILE}"

  log_step "Step 2/5  Extract public key"
  local pubkey
  pubkey="$(grep -E '^# public key: ' "${AGE_KEY_FILE}" | awk '{print $4}')"
  [[ -n "${pubkey}" ]] || die "Could not read public key from ${AGE_KEY_FILE}"
  log_ok "Public key:"
  printf '\n  %s%s%s\n\n' "${C_BOLD}" "${pubkey}" "${C_RESET}"

  log_step "Step 3/5  Update .sops.yaml"
  cat <<EOF
Edit ${REPO_ROOT}/.sops.yaml and replace the &admin anchor with the public
key printed above. The current placeholder is:

  - &admin     age1qzg9z6yq0bootstrapwith...

After editing, save and continue.
EOF
  if confirm "Open .sops.yaml in \$EDITOR now?"; then
    "${EDITOR:-vi}" "${REPO_ROOT}/.sops.yaml"
  else
    log_info "Skipping editor open — edit .sops.yaml yourself before encrypting."
  fi

  log_step "Step 4/5  Cluster recipient (TODO marker)"
  cat <<EOF
The second &cluster recipient in .sops.yaml is generated INSIDE the cluster
on first bootstrap. The Flux 'sops-age' Secret in namespace 'flux-system'
holds the matching private key. bootstrap.sh installs that secret.

For now, leave the &cluster placeholder in .sops.yaml as-is. After the cluster
is up, run:

  KUBECONFIG=~/.kube/config-homelab \\
    kubectl get secret sops-age -n flux-system \\
    -o jsonpath='{.data.age\.agekey}' | base64 -d

…to read its public key, then update &cluster, then sops-updatekeys again.
EOF

  log_step "Step 5/5  Re-encrypt existing SOPS files"
  cat <<EOF
After updating .sops.yaml, propagate the new recipient set to every encrypted
file:

  ${C_BOLD}cd ${REPO_ROOT}${C_RESET}
  ${C_BOLD}find . -type f -name '*.sops.*' -not -path './.git/*' \\
      -exec sops updatekeys -y {} \;${C_RESET}

This is non-destructive — each file is rewritten in place, the encrypted
payload changes, the plaintext does not.
EOF
  log_ok "bootstrap-secrets.sh done."
}

main "$@"
