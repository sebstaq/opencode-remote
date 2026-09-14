#!/usr/bin/env bash
# Load repo-root .env into the environment. Existing environment variables win.
# Values must not be quoted with spaces needing escapes; simple KEY=VALUE lines.

_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -f "${_repo_root}/.env" ]]; then
  while IFS='=' read -r _k _v || [[ -n "$_k" ]]; do
    _k="${_k%%$'\r'}"
    [[ -z "$_k" || "$_k" == \#* ]] && continue
    _v="${_v%%$'\r'}"
    _v="${_v%\"}"; _v="${_v#\"}"
    _v="${_v%\'}"; _v="${_v#\'}"
    if [[ -z "${!_k:-}" ]]; then
      export "${_k}=${_v}"
    fi
  done < "${_repo_root}/.env"
fi
unset _repo_root _k _v
