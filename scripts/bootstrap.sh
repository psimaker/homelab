#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap.sh — full first-deploy of the homelab from an empty cloud account
# to a reconciling Flux cluster.
#
# Flow (each step is a function, top-to-bottom readable):
#   1. preflight_tools         — verify CLIs are present
#   2. preflight_age_key       — ensure SOPS age private key exists
#   3. tofu_apply              — provision Hetzner + Cloudflare + B2
#   4. wait_for_edge_ssh       — block until the new edge node is reachable
#   5. ansible_apply           — run site.yml (baseline, tailscale, k3s, ...)
#   6. fetch_kubeconfig        — verify ~/.kube/config-homelab landed
#   7. install_sops_age_secret — push the age key into the cluster
#   8. flux_bootstrap          — bootstrap Flux against Gitea
#   9. wait_for_infrastructure — block until infrastructure Kustomization is Ready
#  10. summary                 — final URLs + next steps
#
# Usage:
#   ./scripts/bootstrap.sh                 # interactive, confirms each mutation
#   ./scripts/bootstrap.sh --unattended    # skip confirmations, suitable for CI
#   ./scripts/bootstrap.sh --help
#
# Prerequisites:
#   - Operator workstation with: tofu, ansible-playbook, kubectl, flux, sops, age
#   - Network reachability to git.psimaker.org (CI runner or VPN)
#   - terraform/live/prod/terraform.tfvars.sops.json populated and decryptable
#   - Inventory in ansible/inventory/hosts.yml correct for the deployment
#   - SSH key ~/.ssh/id_ed25519_homelab loaded (or override SSH_KEY)
#
# Architecture reference: docs/architecture.md, section "Bootstrap sequence"
# ---------------------------------------------------------------------------
set -euo pipefail

# Require bash 4+ for associative arrays (macOS ships /bin/bash 3.2; this
# script's shebang uses /usr/bin/env bash so a newer one from brew works).
if (( BASH_VERSINFO[0] < 4 )); then
  printf '[FAIL] bash >= 4 required (found %s). On macOS: brew install bash\n' \
    "${BASH_VERSION}" >&2
  exit 1
fi

# ---- repo root + paths -----------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform/live/prod"
ANSIBLE_DIR="${REPO_ROOT}/ansible"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${HOME}/.kube/config-homelab}"
AGE_KEY_FILE="${AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}"

# ---- runtime flags ---------------------------------------------------------
UNATTENDED=0
SKIP_TOFU=0
SKIP_ANSIBLE=0
SKIP_FLUX=0

# ---- colour log helpers ----------------------------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi

log_info()    { printf '%s[INFO]%s %s\n'  "${C_YELLOW}" "${C_RESET}" "$*"; }
log_ok()      { printf '%s[OK]%s   %s\n'  "${C_GREEN}"  "${C_RESET}" "$*"; }
log_warn()    { printf '%s[WARN]%s %s\n'  "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
log_fail()    { printf '%s[FAIL]%s %s\n'  "${C_RED}"    "${C_RESET}" "$*" >&2; }
log_step()    { printf '\n%s%s== %s ==%s\n' "${C_BOLD}" "${C_BLUE}" "$*" "${C_RESET}"; }

die() { log_fail "$*"; exit 1; }

confirm() {
  local prompt="${1:-Continue?}"
  if (( UNATTENDED == 1 )); then
    log_info "Unattended mode: auto-confirming '${prompt}'"
    return 0
  fi
  read -r -p "${C_BOLD}${prompt}${C_RESET} [y/N] " reply
  [[ "${reply}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ---- usage -----------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Full bootstrap: OpenTofu apply → Ansible site → Flux bootstrap.

Options:
  --unattended       Skip confirmation prompts (for CI use only).
  --skip-tofu        Skip the OpenTofu apply step (cluster already exists).
  --skip-ansible     Skip the Ansible site.yml step.
  --skip-flux        Skip the Flux bootstrap step.
  -h, --help         Show this help.

Environment overrides:
  KUBECONFIG_PATH    Where to fetch the kubeconfig (default: ~/.kube/config-homelab)
  AGE_KEY_FILE       SOPS age private key path (default: ~/.config/sops/age/keys.txt)
  GITEA_HOSTNAME     Gitea host for flux bootstrap (default: git.psimaker.org)
  GITEA_OWNER        Repo owner (default: umut.erdem)
  GITEA_REPO         Repo name (default: homelab)

Architecture: docs/architecture.md, section "Bootstrap sequence".
EOF
}

# ---- arg parse -------------------------------------------------------------
while (( $# > 0 )); do
  case "$1" in
    --unattended)   UNATTENDED=1 ;;
    --skip-tofu)    SKIP_TOFU=1 ;;
    --skip-ansible) SKIP_ANSIBLE=1 ;;
    --skip-flux)    SKIP_FLUX=1 ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Step 1: preflight — required CLIs
# ---------------------------------------------------------------------------
preflight_tools() {
  log_step "Step 1/10  Pre-flight: required CLI tools"

  local -A install_hint=(
    [tofu]="https://opentofu.org/docs/intro/install/  (or: brew install opentofu)"
    [ansible-playbook]="pipx install ansible-core==2.18.* (or apt install ansible)"
    [kubectl]="https://kubernetes.io/docs/tasks/tools/  (or: brew install kubectl)"
    [flux]="https://fluxcd.io/flux/installation/         (or: brew install fluxcd/tap/flux)"
    [sops]="https://github.com/getsops/sops             (or: brew install sops)"
    [age]="https://github.com/FiloSottile/age           (or: brew install age)"
    [age-keygen]="ships alongside the 'age' package"
    [ssh]="usually preinstalled; install openssh-client otherwise"
    [jq]="brew install jq  (or: apt install jq)"
  )

  local missing=()
  for cmd in tofu ansible-playbook kubectl flux sops age age-keygen ssh jq; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    log_fail "Missing CLIs: ${missing[*]}"
    echo
    for cmd in "${missing[@]}"; do
      printf '  %-20s %s\n' "${cmd}:" "${install_hint[${cmd}]:-(no hint)}"
    done
    echo
    die "Install the missing tools and re-run."
  fi
  log_ok "All required CLIs present."
}

# ---------------------------------------------------------------------------
# Step 2: preflight — age private key, run bootstrap-secrets.sh if absent
# ---------------------------------------------------------------------------
preflight_age_key() {
  log_step "Step 2/10  Pre-flight: SOPS age private key"

  if [[ -f "${AGE_KEY_FILE}" ]]; then
    log_ok "Found age key at ${AGE_KEY_FILE}"
    return 0
  fi

  log_warn "No age key at ${AGE_KEY_FILE}"
  log_info "Running scripts/bootstrap-secrets.sh to generate one."
  if ! confirm "Generate a new age keypair now?"; then
    die "Cannot continue without an age key. Bail."
  fi
  "${SCRIPT_DIR}/bootstrap-secrets.sh"

  if [[ ! -f "${AGE_KEY_FILE}" ]]; then
    die "bootstrap-secrets.sh did not produce ${AGE_KEY_FILE}"
  fi
  log_ok "Age key in place."
}

# ---------------------------------------------------------------------------
# Step 3: OpenTofu apply
# ---------------------------------------------------------------------------
tofu_apply() {
  log_step "Step 3/10  OpenTofu: provision cloud resources"

  if (( SKIP_TOFU == 1 )); then
    log_warn "--skip-tofu set, jumping to Ansible."
    return 0
  fi

  [[ -d "${TERRAFORM_DIR}" ]] || die "Missing ${TERRAFORM_DIR}"

  log_info "Working dir: ${TERRAFORM_DIR}"
  log_info "Initialising backend (Hetzner Object Storage)."
  ( cd "${TERRAFORM_DIR}" && tofu init -input=false )

  log_info "Generating plan."
  ( cd "${TERRAFORM_DIR}" && tofu plan -input=false -out=tfplan.bin )

  if ! confirm "Apply the plan above to PROD?"; then
    die "Plan rejected. Bail."
  fi

  log_info "Applying."
  ( cd "${TERRAFORM_DIR}" && tofu apply -input=false -auto-approve tfplan.bin )
  rm -f "${TERRAFORM_DIR}/tfplan.bin"

  log_ok "OpenTofu apply complete."
}

# ---------------------------------------------------------------------------
# Step 4: wait for edge SSH
# ---------------------------------------------------------------------------
wait_for_edge_ssh() {
  log_step "Step 4/10  Waiting for edge node SSH reachability"

  if (( SKIP_ANSIBLE == 1 )); then
    log_warn "--skip-ansible set; skipping SSH wait."
    return 0
  fi

  local edge_host
  edge_host="$(
    cd "${ANSIBLE_DIR}" \
      && ansible-inventory -i inventory/hosts.yml --host edge 2>/dev/null \
      | jq -r '.ansible_host // empty'
  )"
  [[ -n "${edge_host}" ]] || die "Could not resolve edge ansible_host from inventory."

  log_info "Probing ssh ${edge_host} (timeout 5m, 5s between attempts)..."
  local -i attempts=0 max=60
  while (( attempts < max )); do
    if ssh -o BatchMode=yes \
           -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=accept-new \
           -o UserKnownHostsFile=/dev/null \
           "${edge_host}" true 2>/dev/null; then
      log_ok "SSH reachable on attempt $((attempts+1))."
      return 0
    fi
    attempts+=1
    printf '.'
    sleep 5
  done
  echo
  die "edge SSH never came up after $((max * 5))s. Check Hetzner console."
}

# ---------------------------------------------------------------------------
# Step 5: Ansible site.yml
# ---------------------------------------------------------------------------
ansible_apply() {
  log_step "Step 5/10  Ansible: configure hosts (baseline, tailscale, k3s)"

  if (( SKIP_ANSIBLE == 1 )); then
    log_warn "--skip-ansible set, jumping to Flux."
    return 0
  fi

  [[ -d "${ANSIBLE_DIR}" ]] || die "Missing ${ANSIBLE_DIR}"

  if ! confirm "Run ansible-playbook playbooks/site.yml against airbase + edge?"; then
    die "Ansible step rejected. Bail."
  fi

  log_info "Running site.yml (this will take a while; k3s install is the slow bit)."
  ( cd "${ANSIBLE_DIR}" && ansible-playbook -i inventory/hosts.yml playbooks/site.yml )

  log_ok "Ansible apply complete."
}

# ---------------------------------------------------------------------------
# Step 6: verify kubeconfig
# ---------------------------------------------------------------------------
fetch_kubeconfig() {
  log_step "Step 6/10  Verify kubeconfig at ${KUBECONFIG_PATH}"

  if [[ ! -s "${KUBECONFIG_PATH}" ]]; then
    die "Expected ${KUBECONFIG_PATH} to be populated by the k3s_server role. Not found."
  fi

  log_info "Trying kubectl get nodes via ${KUBECONFIG_PATH}..."
  if ! KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes >/dev/null 2>&1; then
    die "kubectl cannot reach the API server. Check Tailscale + the k3s_server role."
  fi

  log_ok "Cluster reachable. Nodes:"
  KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes
}

# ---------------------------------------------------------------------------
# Step 7: install sops-age secret in cluster
# ---------------------------------------------------------------------------
install_sops_age_secret() {
  log_step "Step 7/10  Install Secret/sops-age in flux-system namespace"

  export KUBECONFIG="${KUBECONFIG_PATH}"

  log_info "Ensuring flux-system namespace exists."
  kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

  log_info "Applying Secret/sops-age (data redacted from log)."
  kubectl create secret generic sops-age \
    --namespace=flux-system \
    --from-file=age.agekey="${AGE_KEY_FILE}" \
    --dry-run=client -o yaml \
    | kubectl apply -f -

  log_ok "sops-age secret in place — Flux will be able to decrypt."
}

# ---------------------------------------------------------------------------
# Step 8: flux bootstrap against gitea
# ---------------------------------------------------------------------------
flux_bootstrap() {
  log_step "Step 8/10  flux bootstrap gitea"

  if (( SKIP_FLUX == 1 )); then
    log_warn "--skip-flux set, jumping to convergence wait."
    return 0
  fi

  : "${GITEA_HOSTNAME:=git.psimaker.org}"
  : "${GITEA_OWNER:=umut.erdem}"
  : "${GITEA_REPO:=homelab}"

  if [[ -z "${GITEA_TOKEN:-}" ]]; then
    log_warn "GITEA_TOKEN env var is not set. flux will prompt or fail."
    log_info "Generate one at https://${GITEA_HOSTNAME}/user/settings/applications"
    if ! confirm "Continue without it (flux will prompt)?"; then
      die "Bail. Set GITEA_TOKEN and re-run."
    fi
  fi

  export KUBECONFIG="${KUBECONFIG_PATH}"
  log_info "Bootstrapping Flux against ${GITEA_HOSTNAME}/${GITEA_OWNER}/${GITEA_REPO}"
  flux bootstrap gitea \
    --hostname="${GITEA_HOSTNAME}" \
    --owner="${GITEA_OWNER}" \
    --repository="${GITEA_REPO}" \
    --path=kubernetes \
    --branch=main \
    --personal=false

  log_ok "flux bootstrap complete."
}

# ---------------------------------------------------------------------------
# Step 9: wait for infrastructure Kustomization to converge
# ---------------------------------------------------------------------------
wait_for_infrastructure() {
  log_step "Step 9/10  Waiting for infrastructure Kustomization to be Ready"

  export KUBECONFIG="${KUBECONFIG_PATH}"
  local -i attempts=0 max=60   # 30 min @ 30s
  while (( attempts < max )); do
    local status
    status="$(flux get kustomization infrastructure -n flux-system --no-header 2>/dev/null || true)"
    if [[ "${status}" == *"True"* ]]; then
      log_ok "infrastructure Kustomization is Ready (attempt $((attempts+1)))."
      return 0
    fi
    attempts+=1
    printf '.'
    sleep 30
  done
  echo
  log_warn "infrastructure did not converge in $((max * 30))s."
  log_warn "Last status:"
  flux get kustomization infrastructure -n flux-system || true
  die "Flux convergence timed out. Inspect with: flux logs --all-namespaces"
}

# ---------------------------------------------------------------------------
# Step 10: summary
# ---------------------------------------------------------------------------
summary() {
  log_step "Step 10/10  Bootstrap complete"

  cat <<EOF

  ${C_GREEN}${C_BOLD}Cluster is reconciling.${C_RESET}

  Useful follow-ups:
    flux get all -A                   # cluster-wide reconciliation status
    flux logs --all-namespaces        # if anything looks unhappy
    kubectl get nodes,pods -A         # raw view

  Live links:
    Production:   https://loogi.ch
    Source:       https://${GITEA_HOSTNAME:-git.psimaker.org}/${GITEA_OWNER:-umut.erdem}/${GITEA_REPO:-homelab}
    Mirror:       https://github.com/psimaker/homelab
    Headscale:    https://hs.psimaker.org    (after identity Kustomization is Ready)
    Pocket-ID:    https://id.psimaker.org    (after identity Kustomization is Ready)

  Next steps:
    1. Wait for the 'apps' Kustomization to converge (LOOGI deploy).
    2. Verify https://loogi.ch resolves and serves a search page.
    3. Wire up Renovate by checking the 'renovate' namespace cronjob.

EOF
}

main() {
  preflight_tools
  preflight_age_key
  tofu_apply
  wait_for_edge_ssh
  ansible_apply
  fetch_kubeconfig
  install_sops_age_secret
  flux_bootstrap
  wait_for_infrastructure
  summary
}

main "$@"
