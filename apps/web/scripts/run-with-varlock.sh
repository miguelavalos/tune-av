#!/usr/bin/env bash
set -euo pipefail

profile="${TUNEAV_INFISICAL_PROFILE:-local}"
if [ "${1:-}" = "--profile" ]; then
  profile="${2:-}"
  shift 2
fi

web_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$(cd "$web_root/../.." && pwd)"
varlock_bin="$repo_root/node_modules/.bin/varlock"

eval "$("$repo_root/scripts/resolve-infisical-bootstrap-env.sh" "$profile")"

if [ ! -x "$varlock_bin" ]; then
  echo "varlock CLI is required. Run 'bun install' from the repo root." >&2
  exit 1
fi

export_from_varlock() {
  local source_key="$1"
  local target_key="$2"
  local required="${3:-required}"
  local value="${!target_key:-}"

  if [ -z "$value" ] && [ -n "${!source_key:-}" ]; then
    value="${!source_key}"
  fi

  if [ -z "$value" ]; then
    value="$("$varlock_bin" printenv --path "$repo_root" "$source_key" 2>/dev/null || true)"
  fi

  if [ -z "$value" ] && [ "$required" = "required" ]; then
    echo "$source_key is required. Provide it through Varlock/Infisical or as an environment variable." >&2
    exit 1
  fi

  if [ -n "$value" ]; then
    export "$target_key=$value"
  fi
}

export_from_varlock "ACCOUNTAV_PUBLISHABLE_KEY" "VITE_ACCOUNTAV_PUBLISHABLE_KEY"
export_from_varlock "ACCOUNTAV_PUBLISHABLE_KEY" "CLERK_PUBLISHABLE_KEY"
export_from_varlock "ACCOUNTAV_SECRET_KEY" "CLERK_SECRET_KEY"
export_from_varlock "ACCOUNTAV_API_BASE_URL" "VITE_ACCOUNTAV_API_BASE_URL"
export_from_varlock "TUNEAV_API_BASE_URL" "VITE_TUNEAV_API_BASE_URL" optional
export_from_varlock "TUNEAV_CONVEX_URL" "VITE_TUNEAV_CONVEX_URL" optional
export_from_varlock "TUNEAV_TERMS_URL" "VITE_TUNEAV_TERMS_URL" optional
export_from_varlock "TUNEAV_PRIVACY_URL" "VITE_TUNEAV_PRIVACY_URL" optional
export_from_varlock "ACCOUNTAV_MANAGEMENT_URL" "VITE_ACCOUNTAV_MANAGEMENT_URL" optional
export_from_varlock "SUPPORTAV_BASE_URL" "VITE_SUPPORTAV_BASE_URL" optional
export_from_varlock "TUNEAV_SUPPORT_EMAIL" "VITE_TUNEAV_SUPPORT_EMAIL" optional
export_from_varlock "TUNEAV_OPEN_SOURCE_URL" "VITE_TUNEAV_OPEN_SOURCE_URL" optional

exec "$@"
