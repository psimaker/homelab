#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# rotate-age-key.sh — annual SOPS age-key rotation, rehearsable.
#
# This script DOES the work (so the rotation is real, end-to-end) and PROMPTS
# at every irreversible step (so a human can bail without trashing
# encrypted state). Running it through to the end produces a fully rotated
# repository with the new key set as the sole admin recipient.
#
# Steps (each is one function below, idempotent where possible):
#   1. generate_new_keypair   — `age-keygen` -> ${AGE_KEY_FILE}.new
#   2. add_new_recipient      — append the new pubkey to .sops.yaml
#   3. updatekeys_first_pass  — `sops updatekeys` over every *.sops.* file
#   4. update_cluster_secret  — patch flux-system/sops-age with the new key
#   5. update_ci_secret       — instructions for SOPS_AGE_KEY in CI
#   6. wait_overnight         — explicit pause: 24h verification window
#   7. remove_old_recipient   — strip the previous &admin from .sops.yaml
#   8. updatekeys_second_pass — re-encrypt without the old recipient
#   9. archive_old_key        — mv keys.txt -> keys.txt.archived-YYYY-MM-DD
#
# Usage:
#   ./scripts/rotate-age-key.sh                  # interactive, prompts at each
#   ./scripts/rotate-age-key.sh --resume STEP    # resume from step N (1-9)
#   ./scripts/rotate-age-key.sh --help
#
# Prerequisites:
#   - age, age-keygen, sops, kubectl on PATH
#   - KUBECONFIG pointing at the cluster (default: ~/.kube/config-homelab)
#   - Repo working tree clean (we will modify .sops.yaml + every *.sops.*)
#
# Architecture: docs/architecture.md, "Day-2 operations -> Rotating the age key"
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGE_KEY_FILE="${AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"
NEW_AGE_KEY_FILE="${AGE_KEY_FILE}.new"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${HOME}/.kube/config-homelab}"
SOPS_CONFIG="${REPO_ROOT}/.sops.yaml"

RESUME_FROM=1

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
  read -r -p "${C_BOLD}${prompt}${C_RESET} [y/N] " reply
  [[ "${reply}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

usage() {
  cat <<EOF
Usage: $0 [--resume N] [--help]

Rotates the SOPS age admin key end-to-end. Prompts at every mutation.

Options:
  --resume N    Start from step N (1..9). Useful if a previous run was
                interrupted between updatekeys passes.
  -h, --help    Show this help.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --resume) RESUME_FROM="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

# Helper: list every SOPS-encrypted file under the repo, deterministically.
list_sops_files() {
  ( cd "${REPO_ROOT}" \
      && git ls-files -z 2>/dev/null \
        | tr '\0' '\n' \
        | grep -E '\.sops\.(ya?ml|json|env|toml|ini)$' \
        || true )
}

# Helper: extract pubkey from a keys.txt-formatted file.
pubkey_of() {
  local kf="$1"
  grep -E '^# public key: ' "${kf}" | awk '{print $4}'
}

# ---------------------------------------------------------------------------
# Step 1
# ---------------------------------------------------------------------------
generate_new_keypair() {
  log_step "Step 1/9  Generate new age keypair"

  command -v age-keygen >/dev/null || die "age-keygen not on PATH"
  if [[ -f "${NEW_AGE_KEY_FILE}" ]]; then
    log_warn "${NEW_AGE_KEY_FILE} already exists."
    if ! confirm "Overwrite the existing pre-generated key?"; then
      log_info "Reusing existing ${NEW_AGE_KEY_FILE}"
      return 0
    fi
  fi

  age-keygen -o "${NEW_AGE_KEY_FILE}"
  chmod 600 "${NEW_AGE_KEY_FILE}"
  log_ok "Wrote ${NEW_AGE_KEY_FILE}"
  log_info "New public key: $(pubkey_of "${NEW_AGE_KEY_FILE}")"
}

# ---------------------------------------------------------------------------
# Step 2
# ---------------------------------------------------------------------------
add_new_recipient() {
  log_step "Step 2/9  Add new recipient to .sops.yaml"

  [[ -f "${SOPS_CONFIG}" ]] || die "Missing ${SOPS_CONFIG}"

  local new_pub
  new_pub="$(pubkey_of "${NEW_AGE_KEY_FILE}")"
  [[ -n "${new_pub}" ]] || die "Could not read pubkey from ${NEW_AGE_KEY_FILE}"

  if grep -q "${new_pub}" "${SOPS_CONFIG}"; then
    log_info "New pubkey already present in .sops.yaml — skipping insert."
    return 0
  fi

  cat <<EOF
You are about to ADD this recipient to ${SOPS_CONFIG}:

  - &admin_new ${new_pub}

…and reference it (alongside the existing &admin) in every age: list. The
mechanical edit is fiddly enough that we recommend doing it by hand:

  1. Open ${SOPS_CONFIG} in \$EDITOR
  2. Add a new anchor:    - &admin_new ${new_pub}
  3. In every key_groups.age list, ADD '*admin_new' next to '*admin'
  4. Save

The next step (sops updatekeys) will re-encrypt every file to BOTH old and
new recipients, so you can decrypt with either key during the verification
window.
EOF
  if confirm "Open ${SOPS_CONFIG} in \$EDITOR now?"; then
    "${EDITOR:-vi}" "${SOPS_CONFIG}"
  fi
  if ! grep -q "${new_pub}" "${SOPS_CONFIG}"; then
    die "New pubkey still not in .sops.yaml — bail."
  fi
  log_ok ".sops.yaml updated."
}

# ---------------------------------------------------------------------------
# Step 3
# ---------------------------------------------------------------------------
updatekeys_first_pass() {
  log_step "Step 3/9  sops updatekeys (first pass — both recipients)"

  command -v sops >/dev/null || die "sops not on PATH"

  local files
  mapfile -t files < <(list_sops_files)
  if (( ${#files[@]} == 0 )); then
    log_warn "No *.sops.* files tracked in git — nothing to re-encrypt."
    return 0
  fi

  log_info "Will re-encrypt ${#files[@]} files."
  if ! confirm "Run 'sops updatekeys -y' over all of them?"; then
    die "Bail."
  fi

  local f
  for f in "${files[@]}"; do
    printf '  -> %s\n' "${f}"
    ( cd "${REPO_ROOT}" && sops updatekeys -y "${f}" )
  done
  log_ok "First-pass updatekeys complete."
}

# ---------------------------------------------------------------------------
# Step 4
# ---------------------------------------------------------------------------
update_cluster_secret() {
  log_step "Step 4/9  Update Secret/sops-age in flux-system"

  command -v kubectl >/dev/null || die "kubectl not on PATH"
  [[ -f "${KUBECONFIG_PATH}" ]] || die "kubeconfig not at ${KUBECONFIG_PATH}"

  if ! confirm "Patch in-cluster Secret/sops-age with the NEW private key?"; then
    log_warn "Skipped. Flux will still decrypt with the OLD key — that's fine"
    log_warn "during the verification window. Re-run with --resume 4 later."
    return 0
  fi

  KUBECONFIG="${KUBECONFIG_PATH}" \
    kubectl create secret generic sops-age \
      --namespace=flux-system \
      --from-file=age.agekey="${NEW_AGE_KEY_FILE}" \
      --dry-run=client -o yaml \
      | KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f -

  log_info "Forcing source-controller to pick up the new key."
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl rollout restart \
    deployment/kustomize-controller -n flux-system || true

  log_ok "Cluster secret rotated."
}

# ---------------------------------------------------------------------------
# Step 5
# ---------------------------------------------------------------------------
update_ci_secret() {
  log_step "Step 5/9  Update SOPS_AGE_KEY in CI"

  cat <<EOF
The CI runner uses the SOPS_AGE_KEY environment variable for ansible-apply,
restore-test, and any other workflow that needs to decrypt. Update it in:

  Gitea:  https://git.example.com/umut.erdem/homelab → Settings → Actions → Secrets
  GitHub: not used (mirror only; CI runs on Gitea)

The new private key value is the FULL file contents:

  cat ${NEW_AGE_KEY_FILE}

Paste it as the value of the secret named SOPS_AGE_KEY.
EOF
  confirm "Done updating CI secrets?" || die "Bail. Re-run with --resume 5."
  log_ok "CI secret rotated (per operator confirmation)."
}

# ---------------------------------------------------------------------------
# Step 6
# ---------------------------------------------------------------------------
wait_overnight() {
  log_step "Step 6/9  Verification window (24h)"

  cat <<EOF
Right now both keys decrypt every file. Live with that for at least 24h, then
run any flux/ansible workflow you care about and confirm it works:

  flux reconcile source git flux-system
  flux reconcile kustomization infrastructure
  ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml --check

If anything blows up, you still have the OLD key on disk — restore the
previous .sops.yaml from git (\`git checkout HEAD -- .sops.yaml\`) and rerun
\`sops updatekeys\` with --resume 3.

When you're satisfied, re-run this script with:

  ./scripts/rotate-age-key.sh --resume 7
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Step 7
# ---------------------------------------------------------------------------
remove_old_recipient() {
  log_step "Step 7/9  Remove OLD recipient from .sops.yaml"

  cat <<EOF
Now strip the OLD &admin recipient from ${SOPS_CONFIG}:

  1. Open ${SOPS_CONFIG} in \$EDITOR
  2. Delete the OLD &admin anchor line
  3. Rename &admin_new to &admin in BOTH the anchor and every reference
  4. Save

After this point, the OLD key is dead — only the NEW key can decrypt the
re-encrypted files.
EOF
  if ! confirm "Open ${SOPS_CONFIG} in \$EDITOR now?"; then
    die "Bail."
  fi
  "${EDITOR:-vi}" "${SOPS_CONFIG}"

  local old_pub
  old_pub="$(pubkey_of "${AGE_KEY_FILE}")"
  if grep -q "${old_pub}" "${SOPS_CONFIG}"; then
    die "Old pubkey ${old_pub} still in ${SOPS_CONFIG}. Edit again."
  fi
  log_ok ".sops.yaml no longer references the old key."
}

# ---------------------------------------------------------------------------
# Step 8
# ---------------------------------------------------------------------------
updatekeys_second_pass() {
  log_step "Step 8/9  sops updatekeys (second pass — new recipient only)"

  local files
  mapfile -t files < <(list_sops_files)
  if (( ${#files[@]} == 0 )); then
    log_warn "Nothing to re-encrypt."; return 0
  fi

  if ! confirm "Re-encrypt ${#files[@]} files? (irreversible — old key dies after this)"; then
    die "Bail."
  fi

  local f
  for f in "${files[@]}"; do
    printf '  -> %s\n' "${f}"
    ( cd "${REPO_ROOT}" && sops updatekeys -y "${f}" )
  done
  log_ok "Second-pass updatekeys complete."
}

# ---------------------------------------------------------------------------
# Step 9
# ---------------------------------------------------------------------------
archive_old_key() {
  log_step "Step 9/9  Archive old key, promote new key"

  local stamp
  stamp="$(date -u +%Y-%m-%d)"
  local archived="${AGE_KEY_FILE}.archived-${stamp}"

  if [[ ! -f "${AGE_KEY_FILE}" ]]; then
    log_warn "No old key at ${AGE_KEY_FILE} — nothing to archive."
  else
    if [[ -f "${archived}" ]]; then
      die "Archive path already exists: ${archived}"
    fi
    mv "${AGE_KEY_FILE}" "${archived}"
    chmod 400 "${archived}"
    log_ok "Old key archived to ${archived}"
  fi

  if [[ -f "${NEW_AGE_KEY_FILE}" ]]; then
    mv "${NEW_AGE_KEY_FILE}" "${AGE_KEY_FILE}"
    chmod 600 "${AGE_KEY_FILE}"
    log_ok "New key promoted to ${AGE_KEY_FILE}"
  fi

  cat <<EOF

  Rotation complete. Next housekeeping items:
  - Commit + push the .sops.yaml + re-encrypted files (one PR titled
    'chore(secrets): rotate age key YYYY-Q1').
  - Add a calendar reminder for next year.
  - Verify CI green on the rotation PR before merging.

EOF
}

# ---------------------------------------------------------------------------
main() {
  local steps=(
    generate_new_keypair
    add_new_recipient
    updatekeys_first_pass
    update_cluster_secret
    update_ci_secret
    wait_overnight
    remove_old_recipient
    updatekeys_second_pass
    archive_old_key
  )

  if ! [[ "${RESUME_FROM}" =~ ^[1-9]$ ]]; then
    die "--resume must be 1..9 (got ${RESUME_FROM})"
  fi

  local i
  for (( i = RESUME_FROM - 1; i < ${#steps[@]}; i++ )); do
    "${steps[$i]}"
  done
}

main "$@"
