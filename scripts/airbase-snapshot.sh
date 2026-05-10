#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# airbase-snapshot.sh — quarterly re-sync of compose/ with what airbase
# actually runs.
#
# For each Tier-2 stack:
#   1. scp the live compose file from airbase:/data/<stack>/<file> to a
#      temp dir
#   2. parse it for ${VAR} / ${VAR:-default} references
#   3. apply secret-redaction patterns (raw values get lifted to ${VAR})
#   4. write a sanitised copy into compose/<stack>/
#   5. generate a .env.example listing every referenced var with a TODO
#   6. write a small README.md from a known lookup table
#   7. drop a .gitignore that blocks the real .env
#
# This is read-only on airbase (we only scp out, never push). Run it from
# the operator workstation.
#
# Usage:
#   ./scripts/airbase-snapshot.sh                       # all stacks
#   ./scripts/airbase-snapshot.sh n8n vaultwarden       # subset
#   ./scripts/airbase-snapshot.sh --list                # show known stacks
#   ./scripts/airbase-snapshot.sh --dry-run             # don't write
#   ./scripts/airbase-snapshot.sh --unattended          # no prompts
#   ./scripts/airbase-snapshot.sh --help
#
# Prerequisites:
#   - SSH access to airbase (default user: umo, key: id_ed25519_homelab)
#   - SSH alias `airbase` resolves; or override with AIRBASE_HOST
#
# Architecture: docs/architecture.md, "Tier-2 — Dataplane".
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${REPO_ROOT}/compose"

AIRBASE_HOST="${AIRBASE_HOST:-airbase}"
AIRBASE_USER="${AIRBASE_USER:-umo}"
AIRBASE_DATA_ROOT="${AIRBASE_DATA_ROOT:-/data}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519_homelab}"

UNATTENDED=0
DRY_RUN=0
OVERWRITE_README=0

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

# ---- known stacks lookup table --------------------------------------------
# Each entry: <stack-name>|<remote-filename>|<public-domain-or-LAN>|<one-liner>
declare -a STACK_TABLE=(
  "adguard|docker-compose.yml|LAN/Tailscale|AdGuardHome split-horizon DNS resolver"
  "arcane|compose.yml|arcane.example.com|Docker management UI"
  "arr-stack|docker-compose.yml|LAN/Tailscale|Sonarr/Radarr/Prowlarr/sabnzbd behind Gluetun"
  "crawl4ai|compose.yml|cluster-internal + LOOGI|Headless web extraction backend"
  "gitea|docker-compose.yml|git.example.com|Self-hosted Git + Actions"
  "gitea-runner|docker-compose.yml|cluster-internal|Gitea Actions runner"
  "grimmory|compose.yml|library.example.com|Self-hosted books library"
  "immich|docker-compose.yml|photos.example.com|Photo library, CUDA-accelerated"
  "n8n|docker-compose.yml|n8n.example.com|Workflow automation"
  "nextcloud-aio|docker-compose.yml|nextcloud.example.com|Nextcloud All-in-One"
  "ntfy|docker-compose.yml|ntfy.example.com|Push-notification server"
  "paperless|docker-compose.yml|docs.example.com|Document archive (paperless-ngx)"
  "plex|docker-compose.yml|LAN/Tailscale|Plex media server"
  "syncthing|docker-compose.yml|syncthing.example.com|File sync incl. VaultSync iOS"
  "vaultwarden|docker-compose.yml|bitwarden.example.com|Self-hosted Bitwarden"
  "watchtower|docker-compose.yml|n/a|Scheduled image-pull on labelled containers"
  "xbrowsersync|docker-compose.yml|bookmarks.example.com|Browser bookmark sync"
)

# ---- secret patterns to redact ---------------------------------------------
# Variable name regexes. Any KEY=VALUE where the KEY matches will get its
# VALUE rewritten to ${KEY} during sanitisation.
SECRET_KEY_PATTERNS=(
  '_API_KEY$'        '_API_TOKEN$'         '_TOKEN$'
  '_SECRET$'         '_SECRET_KEY$'        '_SECRET_TOKEN$'
  '_PASSWORD$'       '_PASS$'              '_PWD$'
  '_AUTH$'           '_OAUTH$'
  '^OPENAI_API_KEY$' '^ANTHROPIC_API_KEY$' '^GOOGLEAI_API_KEY$'
  '^MISTRAL_API_KEY$' '^DEEPSEEK_API_KEY$'
  'PRIVATE_KEY'      'PUBLIC_KEY'          'CERT$'
  '_DSN$'            '_URL$'                # connection strings often contain creds
)

# ---- usage -----------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $0 [STACKS...] [--dry-run] [--unattended] [--list] [--help]

Snapshots Tier-2 Compose stacks from airbase into ${COMPOSE_DIR}/<stack>/.

Args:
  STACKS...        Optional list of stack names. Default: all known stacks.

Options:
  --list           Print known stacks and exit.
  --dry-run        Show what would be written, don't actually write.
  --unattended     Skip confirmations.
  -h, --help       Show this help.

Environment:
  AIRBASE_HOST          SSH alias for airbase (default: airbase)
  AIRBASE_USER          Remote user (default: umo)
  AIRBASE_DATA_ROOT     Compose data root on airbase (default: /data)
  SSH_KEY               SSH private key path
EOF
}

# ---- arg parse -------------------------------------------------------------
ARGS=()
while (( $# > 0 )); do
  case "$1" in
    --dry-run)    DRY_RUN=1 ;;
    --unattended) UNATTENDED=1 ;;
    --list)
      printf 'Known Tier-2 stacks:\n'
      for _row in "${STACK_TABLE[@]}"; do
        IFS='|' read -r _name _file _domain _desc <<<"${_row}"
        printf '  %-15s %-25s %s\n' "${_name}" "${_domain}" "${_desc}"
      done
      exit 0
      ;;
    -h|--help)    usage; exit 0 ;;
    -*)           die "Unknown option: $1 (try --help)" ;;
    *)            ARGS+=("$1") ;;
  esac
  shift
done

# ---- helpers ---------------------------------------------------------------
ssh_airbase() {
  ssh -i "${SSH_KEY}" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      "${AIRBASE_USER}@${AIRBASE_HOST}" "$@"
}

scp_from_airbase() {
  local remote="$1" local_path="$2"
  scp -i "${SSH_KEY}" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      "${AIRBASE_USER}@${AIRBASE_HOST}:${remote}" "${local_path}"
}

# Lookup helper: row by stack name (returns "name|file|domain|desc" or "")
lookup_stack() {
  local q="$1"
  local row
  for row in "${STACK_TABLE[@]}"; do
    IFS='|' read -r name _ _ _ <<<"${row}"
    if [[ "${name}" == "${q}" ]]; then
      printf '%s\n' "${row}"
      return 0
    fi
  done
  return 1
}

# Match "true" if the variable name should be redacted.
should_redact() {
  local var="$1" pat
  for pat in "${SECRET_KEY_PATTERNS[@]}"; do
    if [[ "${var}" =~ ${pat} ]]; then
      return 0
    fi
  done
  return 1
}

# Extract every ${VAR} / ${VAR:-default} reference from a compose file.
# Outputs unique var names, sorted, one per line.
extract_var_refs() {
  local file="$1"
  grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\}' "${file}" \
    | sed -E 's/^\$\{([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
    | sort -u
}

# Replace any KEY: literal-value lines where KEY matches our redact list.
# Best-effort: only handles the common docker-compose `KEY: value` and
# `KEY=value` styles. Anything else stays intact (and a human reviews the
# diff anyway).
sanitise_compose_inline() {
  local in="$1" out="$2"
  python3 - "${in}" "${out}" <<'PY'
import os, re, sys
src, dst = sys.argv[1], sys.argv[2]
SECRET_PATTERNS = [
  r"_API_KEY$", r"_API_TOKEN$", r"_TOKEN$",
  r"_SECRET$", r"_SECRET_KEY$", r"_SECRET_TOKEN$",
  r"_PASSWORD$", r"_PASS$", r"_PWD$",
  r"_AUTH$", r"_OAUTH$",
  r"^OPENAI_API_KEY$", r"^ANTHROPIC_API_KEY$", r"^GOOGLEAI_API_KEY$",
  r"^MISTRAL_API_KEY$", r"^DEEPSEEK_API_KEY$",
  r"PRIVATE_KEY", r"PUBLIC_KEY", r"CERT$",
  r"_DSN$", r"_URL$",
]
COMPILED = [re.compile(p) for p in SECRET_PATTERNS]

def is_secret(name):
  return any(p.search(name) for p in COMPILED)

# Patterns we touch:
#   KEY: literal      ->   KEY: ${KEY}
#   KEY=literal       ->   KEY=${KEY}
# But ONLY when:
#   - the literal is not already a ${...} reference
#   - the key matches our secret pattern list
RE_YAML  = re.compile(r'^(\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:\s*("?)([^"\n]*?)("?)\s*$')
RE_ENV   = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$')

with open(src) as f:
    lines = f.readlines()

out = []
for line in lines:
    stripped = line.rstrip("\n")
    m = RE_YAML.match(stripped)
    if m:
        indent, key, q1, value, q2 = m.groups()
        if value and not value.startswith("${") and is_secret(key):
            out.append(f"{indent}{key}: ${{{key}}}\n")
            continue
    m = RE_ENV.match(stripped)
    if m and not stripped.lstrip().startswith("#"):
        key, value = m.groups()
        if value and not value.startswith("${") and is_secret(key):
            out.append(f"{key}=${{{key}}}\n")
            continue
    out.append(line if line.endswith("\n") else line + "\n")

with open(dst, "w") as f:
    f.writelines(out)
PY
}

# Build .env.example from the union of var refs.
write_env_example() {
  local compose_path="$1" env_path="$2" stack_name="$3" stack_domain="$4"

  if (( DRY_RUN == 1 )); then
    log_info "[dry-run] would write ${env_path}"
    return 0
  fi

  {
    printf '# %s — Tier-2 environment\n' "${stack_name}"
    if [[ "${stack_domain}" != "n/a" ]]; then
      printf '# Public surface: %s\n' "${stack_domain}"
    fi
    printf '# Generated by scripts/airbase-snapshot.sh — fill in real values on airbase only.\n\n'

    local var
    while IFS= read -r var; do
      [[ -z "${var}" ]] && continue
      if should_redact "${var}"; then
        printf '%s=                         # SECRET — generate or copy from existing host\n' "${var}"
      else
        printf '%s=                         # TODO: document\n' "${var}"
      fi
    done < <(extract_var_refs "${compose_path}")
  } > "${env_path}"
}

# Tiny per-stack README.
write_readme() {
  local readme_path="$1" stack_name="$2" stack_domain="$3" stack_desc="$4"
  if (( DRY_RUN == 1 )); then
    log_info "[dry-run] would write ${readme_path}"
    return 0
  fi
  cat > "${readme_path}" <<EOF
# ${stack_name}

${stack_desc}

EOF
  if [[ "${stack_domain}" != "n/a" ]]; then
    printf -- '- Public domain: **%s**\n' "${stack_domain}" >> "${readme_path}"
  fi
  cat >> "${readme_path}" <<EOF
- Snapshot generated by \`scripts/airbase-snapshot.sh\`. The on-host source of
  truth is \`${AIRBASE_DATA_ROOT}/${stack_name}/\` on airbase.
- Real \`.env\` is gitignored; see \`.env.example\` for the variable list.
EOF
}

# .gitignore to block plaintext env from ever sneaking back in.
write_gitignore() {
  local gi_path="$1"
  if (( DRY_RUN == 1 )); then
    log_info "[dry-run] would write ${gi_path}"
    return 0
  fi
  printf '%s\n' '.env' > "${gi_path}"
}

# ---- per-stack snapshot ----------------------------------------------------
snapshot_stack() {
  local row="$1"
  IFS='|' read -r name remote_file domain desc <<<"${row}"

  log_step "Stack: ${name}"

  local out_dir="${COMPOSE_DIR}/${name}"
  local remote_path="${AIRBASE_DATA_ROOT}/${name}/${remote_file}"
  local tmp_in tmp_out
  tmp_in="$(mktemp)"
  tmp_out="$(mktemp)"

  log_info "Pulling ${remote_path}"
  if ! scp_from_airbase "${remote_path}" "${tmp_in}"; then
    log_warn "Could not fetch ${remote_path} — does the file exist on airbase?"
    rm -f "${tmp_in}" "${tmp_out}"
    return 1
  fi

  log_info "Sanitising secret literals -> \${VAR}"
  if command -v python3 >/dev/null 2>&1; then
    sanitise_compose_inline "${tmp_in}" "${tmp_out}"
  else
    log_warn "python3 not found — copying unmodified (review the diff!)"
    cp "${tmp_in}" "${tmp_out}"
  fi

  if (( DRY_RUN == 1 )); then
    log_info "[dry-run] would write ${out_dir}/${remote_file}"
    log_info "[dry-run] referenced vars:"
    extract_var_refs "${tmp_out}" | sed 's/^/    /'
    rm -f "${tmp_in}" "${tmp_out}"
    return 0
  fi

  mkdir -p "${out_dir}"
  cp "${tmp_out}" "${out_dir}/${remote_file}"
  write_env_example "${tmp_out}" "${out_dir}/.env.example" "${name}" "${domain}"
  if [[ ! -f "${out_dir}/README.md" ]] || (( OVERWRITE_README == 1 )); then
    write_readme    "${out_dir}/README.md" "${name}" "${domain}" "${desc}"
  fi
  write_gitignore   "${out_dir}/.gitignore"

  rm -f "${tmp_in}" "${tmp_out}"
  log_ok "Wrote ${out_dir}/{${remote_file},.env.example,README.md,.gitignore}"
}

# ---- main ------------------------------------------------------------------
main() {
  command -v ssh >/dev/null || die "ssh not on PATH"
  command -v scp >/dev/null || die "scp not on PATH"
  [[ -f "${SSH_KEY}" ]] || die "SSH key missing: ${SSH_KEY}"

  log_info "Probing airbase reachability"
  ssh_airbase 'true' || die "Cannot reach airbase via SSH"
  log_ok "airbase reachable"

  local -a targets=()
  if (( ${#ARGS[@]} == 0 )); then
    local row name
    for row in "${STACK_TABLE[@]}"; do
      IFS='|' read -r name _ _ _ <<<"${row}"
      targets+=("${name}")
    done
  else
    targets=("${ARGS[@]}")
  fi

  log_info "Stacks to snapshot: ${targets[*]}"
  if ! confirm "Proceed?"; then
    die "Bail."
  fi

  local stack row failures=0
  for stack in "${targets[@]}"; do
    if row="$(lookup_stack "${stack}")"; then
      snapshot_stack "${row}" || failures=$((failures + 1))
    else
      log_warn "Unknown stack '${stack}' — not in the lookup table. Skipping."
      failures=$((failures + 1))
    fi
  done

  if (( failures > 0 )); then
    log_warn "${failures} stack(s) failed; review log."
    exit 1
  fi
  log_ok "Snapshot complete."
}

main "$@"
