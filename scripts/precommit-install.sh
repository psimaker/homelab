#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# precommit-install.sh — one-shot installer for pre-commit hooks.
#
# Idempotent: safe to re-run; it just re-pins everything to the versions in
# .pre-commit-config.yaml. Run after `git clone` and after every bump to that
# config file.
#
# Usage:
#   ./scripts/precommit-install.sh
#   ./scripts/precommit-install.sh --upgrade   # also bump pre-commit itself
#   ./scripts/precommit-install.sh --help
#
# Prerequisites:
#   - python3 + pipx (preferred) or pip
#   - The repo's .pre-commit-config.yaml present
#
# Architecture: enforces every linter that CI runs in .gitea/workflows/lint.yml.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

UPGRADE=0

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BOLD=""; C_RESET=""
fi
log_info() { printf '%s[INFO]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
log_ok()   { printf '%s[OK]%s   %s\n' "${C_GREEN}"  "${C_RESET}" "$*"; }
log_fail() { printf '%s[FAIL]%s %s\n' "${C_RED}"    "${C_RESET}" "$*" >&2; }
die()      { log_fail "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [--upgrade] [--help]

Installs and registers the pre-commit hooks pinned in .pre-commit-config.yaml.

Options:
  --upgrade      Also \`pip install --upgrade pre-commit\` first.
  -h, --help     Show this help.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --upgrade) UPGRADE=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

[[ -f "${REPO_ROOT}/.pre-commit-config.yaml" ]] \
  || die "Missing ${REPO_ROOT}/.pre-commit-config.yaml"

if ! command -v pre-commit >/dev/null 2>&1; then
  log_info "pre-commit not on PATH; installing."
  if command -v pipx >/dev/null 2>&1; then
    pipx install pre-commit
  elif command -v pip3 >/dev/null 2>&1; then
    pip3 install --user pre-commit
  elif command -v pip >/dev/null 2>&1; then
    pip install --user pre-commit
  else
    die "Need pipx or pip to install pre-commit. See https://pre-commit.com"
  fi
fi

if (( UPGRADE == 1 )); then
  log_info "Upgrading pre-commit."
  if command -v pipx >/dev/null 2>&1; then
    pipx upgrade pre-commit
  else
    pip install --user --upgrade pre-commit
  fi
fi

log_info "pre-commit version: $(pre-commit --version)"
log_info "Installing git hooks (commit-msg, pre-commit, pre-push)."

( cd "${REPO_ROOT}" && pre-commit install --install-hooks --overwrite )
( cd "${REPO_ROOT}" && pre-commit install --hook-type commit-msg --overwrite )
( cd "${REPO_ROOT}" && pre-commit install --hook-type pre-push --overwrite )

log_info "Pre-fetching all hook environments."
( cd "${REPO_ROOT}" && pre-commit install-hooks )

log_ok "Hooks installed. Run \`pre-commit run --all-files\` to verify a clean tree."
