#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# restic-restore-test.sh — automated weekly restore-test.
#
# Picks one of the configured restic repos at random, chooses a recent
# snapshot, restores a known-good fixture path into a tmp dir, and diff-checks
# it against the canonical copy in tests/fixtures/restic-known-good.txt.
#
# Exit codes:
#   0 — restore succeeded AND diff is empty (test passes)
#   1 — restore succeeded but the diff is non-empty (test FAILS — corruption)
#   2 — could not run the restore (env / repo unreachable / no snapshots)
#
# Output (last line) is a Prometheus textfile-collector-formatted metric
# block, suitable for `node_exporter --collector.textfile.directory=...`:
#
#   # HELP restic_restore_test_success Result of the most recent restore test.
#   # TYPE restic_restore_test_success gauge
#   restic_restore_test_success{repo="hostbox"} 1
#   restic_restore_test_duration_seconds{repo="hostbox"} 42
#   restic_restore_test_timestamp_seconds{repo="hostbox"} 1746864000
#
# Usage:
#   ./scripts/restic-restore-test.sh                          # random repo
#   RESTIC_REPO_NAME=hostbox ./scripts/restic-restore-test.sh # specific repo
#   ./scripts/restic-restore-test.sh --textfile /var/lib/node_exporter/textfile/restore.prom
#   ./scripts/restic-restore-test.sh --help
#
# Prerequisites (env vars):
#   RESTIC_PASSWORD                   The restic encryption passphrase
#   HOSTBOX_REPO                      Hetzner Storage Box repo URL
#   B2_REPO                           Backblaze B2 critical-set repo URL
#   B2_ACCOUNT_ID, B2_ACCOUNT_KEY     for the B2 backend if HOSTBOX missing
#
# Architecture: docs/architecture.md, "Backups" — 3-2-1, tested.
# ---------------------------------------------------------------------------
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  printf '[FAIL] bash >= 4 required (found %s)\n' "${BASH_VERSION}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KNOWN_GOOD="${REPO_ROOT}/tests/fixtures/restic-known-good.txt"
FIXTURE_PATH="${RESTORE_FIXTURE_PATH:-/data/restic-fixture/restic-known-good.txt}"
TEXTFILE_OUT=""

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_RESET=""
fi
log_info() { printf '%s[INFO]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
log_ok()   { printf '%s[OK]%s   %s\n' "${C_GREEN}"  "${C_RESET}" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
log_fail() { printf '%s[FAIL]%s %s\n' "${C_RED}"    "${C_RESET}" "$*" >&2; }
die()      { log_fail "$*"; exit 2; }

usage() {
  cat <<EOF
Usage: $0 [--textfile PATH] [--help]

Picks a restic repo, restores a fixture, diffs against tests/fixtures/.

Options:
  --textfile PATH    Write Prometheus textfile metrics to PATH (atomic mv).
                     If unset, metrics are echoed to stdout only.
  -h, --help         Show this help.

Environment:
  RESTIC_REPO_NAME   'hostbox' | 'b2'  Force a specific repo (default: random)
  HOSTBOX_REPO       Restic repo URL for the Hetzner Storage Box
  B2_REPO            Restic repo URL for Backblaze B2 (critical-set)
  RESTIC_PASSWORD    Restic encryption passphrase (REQUIRED)
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --textfile) TEXTFILE_OUT="$2"; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

# ---- metrics writer (defined early so error paths can call it) -------------
emit_metrics() {
  local result="$1" duration="$2" repo="$3" snap="$4" reason="$5"
  local now ts
  now="$(date +%s)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local metrics
  metrics=$(cat <<EOF
# HELP restic_restore_test_success 1 if the latest restic restore-test passed, 0 otherwise.
# TYPE restic_restore_test_success gauge
restic_restore_test_success{repo="${repo}",snapshot="${snap}",reason="${reason}"} ${result}
# HELP restic_restore_test_duration_seconds Wallclock duration of the restore step.
# TYPE restic_restore_test_duration_seconds gauge
restic_restore_test_duration_seconds{repo="${repo}"} ${duration}
# HELP restic_restore_test_timestamp_seconds Unix timestamp of the latest test.
# TYPE restic_restore_test_timestamp_seconds gauge
restic_restore_test_timestamp_seconds{repo="${repo}"} ${now}
EOF
)

  printf '%s\n' "${metrics}"
  printf '# Human-readable: repo=%s snapshot=%s result=%s reason=%s at=%s duration=%ss\n' \
    "${repo}" "${snap}" "${result}" "${reason}" "${ts}" "${duration}"

  if [[ -n "${TEXTFILE_OUT}" ]]; then
    local tmp="${TEXTFILE_OUT}.tmp.$$"
    printf '%s\n' "${metrics}" > "${tmp}"
    mv -f "${tmp}" "${TEXTFILE_OUT}"
    log_info "Wrote metrics to ${TEXTFILE_OUT}"
  fi
}

# ---- pre-flight ------------------------------------------------------------
command -v restic >/dev/null || die "restic not on PATH"
command -v jq     >/dev/null || die "jq not on PATH"
[[ -n "${RESTIC_PASSWORD:-}" ]] || die "RESTIC_PASSWORD must be set"
[[ -f "${KNOWN_GOOD}" ]] || die "Known-good fixture missing: ${KNOWN_GOOD}"

# ---- repo selection --------------------------------------------------------
declare -A REPOS
[[ -n "${HOSTBOX_REPO:-}" ]] && REPOS[hostbox]="${HOSTBOX_REPO}"
[[ -n "${B2_REPO:-}"      ]] && REPOS[b2]="${B2_REPO}"
(( ${#REPOS[@]} > 0 )) || die "Neither HOSTBOX_REPO nor B2_REPO is set"

if [[ -n "${RESTIC_REPO_NAME:-}" ]]; then
  [[ -n "${REPOS[${RESTIC_REPO_NAME}]:-}" ]] \
    || die "RESTIC_REPO_NAME=${RESTIC_REPO_NAME} not configured"
  picked_name="${RESTIC_REPO_NAME}"
else
  # Random pick across configured repos.
  mapfile -t names < <(printf '%s\n' "${!REPOS[@]}")
  picked_name="${names[$((RANDOM % ${#names[@]}))]}"
fi
picked_repo="${REPOS[${picked_name}]}"
export RESTIC_REPOSITORY="${picked_repo}"
log_info "Repo picked: ${picked_name} → ${picked_repo}"

# ---- pick a recent snapshot ------------------------------------------------
log_info "Listing recent snapshots."
snapshots_json="$(restic snapshots --json 2>/dev/null || true)"
if [[ -z "${snapshots_json}" ]] || [[ "${snapshots_json}" == "null" ]]; then
  die "Could not list snapshots in ${picked_name}"
fi

# Take the 5 most recent and pick one at random; oldest-only is a degenerate
# test (it never exercises new chunks).
mapfile -t recent_ids < <(
  printf '%s' "${snapshots_json}" \
    | jq -r 'sort_by(.time) | reverse | .[:5] | .[].short_id'
)
(( ${#recent_ids[@]} > 0 )) || die "No snapshots found in ${picked_name}"
snap_id="${recent_ids[$((RANDOM % ${#recent_ids[@]}))]}"
log_info "Snapshot picked: ${snap_id}"

# ---- restore ---------------------------------------------------------------
tmp_dir="$(mktemp -d -t restic-restore-XXXXXX)"
trap 'rm -rf "${tmp_dir}"' EXIT

start_ts="$(date +%s)"
set +e
restic restore "${snap_id}" \
  --target "${tmp_dir}" \
  --include "${FIXTURE_PATH}"
restore_rc=$?
set -e
end_ts="$(date +%s)"
duration=$((end_ts - start_ts))

if (( restore_rc != 0 )); then
  log_fail "restic restore failed (rc=${restore_rc})"
  emit_metrics 0 "${duration}" "${picked_name}" "${snap_id}" "restore-failed"
  exit 2
fi

# ---- diff ------------------------------------------------------------------
restored_file="${tmp_dir}${FIXTURE_PATH}"
if [[ ! -f "${restored_file}" ]]; then
  log_fail "Restored file missing at ${restored_file}"
  emit_metrics 0 "${duration}" "${picked_name}" "${snap_id}" "missing"
  exit 1
fi

if diff -q "${restored_file}" "${KNOWN_GOOD}" >/dev/null; then
  log_ok "diff is clean (${restored_file} matches known-good)"
  result=1
  reason="ok"
  exit_code=0
else
  log_fail "diff is NON-EMPTY — restored content does not match known-good"
  diff -u "${KNOWN_GOOD}" "${restored_file}" | head -20 >&2 || true
  result=0
  reason="diff"
  exit_code=1
fi

emit_metrics "${result}" "${duration}" "${picked_name}" "${snap_id}" "${reason}"
exit "${exit_code}"
