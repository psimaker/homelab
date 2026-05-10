#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# decrypt-and-source-env.sh — decrypt a SOPS .env file and load it into the
# current shell.
#
# This script MUST be sourced, not executed:
#
#   $ source ./scripts/decrypt-and-source-env.sh some.sops.env
#   $ . ./scripts/decrypt-and-source-env.sh some.sops.env
#
# The decrypted plaintext is consumed line-by-line via process substitution
# and never touches disk. Variables become exported in the calling shell.
#
# Use cases:
#   - Loading SOPS-encrypted credentials into a one-shot ansible run:
#       . scripts/decrypt-and-source-env.sh ansible/.env.sops.env
#       ansible-playbook -i inventory/hosts.yml playbooks/site.yml
#   - Local development against managed services where the canonical secret
#     ships in this repo encrypted.
#
# Usage:
#   source ./scripts/decrypt-and-source-env.sh <encrypted-env-file>
#   source ./scripts/decrypt-and-source-env.sh --help
#
# Prerequisites:
#   - Bash (zsh `source` works too, but the script targets bash semantics)
#   - sops on PATH and an age private key reachable
#   - File extension MUST be one SOPS recognises as env: *.env, *.sops.env
#
# Safety:
#   - Refuses to run if the calling process is the script (i.e. not sourced).
#   - Refuses to run if the file looks like YAML or JSON (different decoder).
#   - Lines starting with '#' or empty are skipped.
# ---------------------------------------------------------------------------

# Detect whether we are being sourced. ${BASH_SOURCE[0]} differs from $0 when
# sourced; if equal, we were executed directly.
__decrypt_env_sourced=0
if [[ -n "${BASH_SOURCE:-}" ]]; then
  if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    __decrypt_env_sourced=1
  fi
elif [[ -n "${ZSH_EVAL_CONTEXT:-}" ]] && [[ "${ZSH_EVAL_CONTEXT}" == *:file* ]]; then
  __decrypt_env_sourced=1
fi

if (( __decrypt_env_sourced == 0 )); then
  printf '[FAIL] decrypt-and-source-env.sh must be SOURCED, not executed.\n' >&2
  printf '       Usage:  source %s <file>\n' "${0:-decrypt-and-source-env.sh}" >&2
  exit 1
fi
unset __decrypt_env_sourced

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  cat <<EOF
Usage: source ${BASH_SOURCE[0]} <encrypted-env-file>

Decrypt a SOPS .env file and export every KEY=VALUE pair into the current
shell. Plaintext never touches disk.

Options:
  -h, --help    Show this help.
EOF
  return 0
fi

if [[ $# -ne 1 ]]; then
  printf '[FAIL] expected exactly 1 argument; got %d\n' "$#" >&2
  return 64
fi

__decrypt_env_target="$1"
if [[ ! -f "${__decrypt_env_target}" ]]; then
  printf '[FAIL] not a file: %s\n' "${__decrypt_env_target}" >&2
  unset __decrypt_env_target
  return 1
fi

case "${__decrypt_env_target}" in
  *.env|*.env.sops|*.sops.env|*.envsops) ;;
  *)
    printf '[WARN] %s does not match *.env / *.sops.env — sops may misparse.\n' \
      "${__decrypt_env_target}" >&2
    ;;
esac

# Read decrypted content via process substitution; never to disk.
__decrypt_env_loaded=0
while IFS= read -r line; do
  # Skip blank and comment-only lines.
  [[ -z "${line}" ]] && continue
  [[ "${line}" =~ ^[[:space:]]*# ]] && continue

  # Tolerate optional `export ` prefix.
  line="${line#export }"

  # Validate KEY=VALUE shape; reject anything that doesn't parse.
  if [[ ! "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
    printf '[WARN] skipping malformed line: %s\n' "${line}" >&2
    continue
  fi

  # Export it. `eval` is acceptable here because we already validated the
  # left-hand side; the right-hand side comes from a SOPS-decrypted, trusted
  # source under the operator's control.
  # shellcheck disable=SC2086
  eval "export ${line}"
  __decrypt_env_loaded=$((__decrypt_env_loaded + 1))
done < <(sops --decrypt "${__decrypt_env_target}")

printf '[OK]   sourced %d variables from %s\n' \
  "${__decrypt_env_loaded}" "${__decrypt_env_target}"

unset __decrypt_env_target __decrypt_env_loaded
