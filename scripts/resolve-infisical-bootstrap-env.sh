#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-local}"

required_keys=(
  INFISICAL_PROJECT_ID
  INFISICAL_ENVIRONMENT
  INFISICAL_CLIENT_ID
  INFISICAL_CLIENT_SECRET
)

case "$profile" in
  local)
    prefix="LOCAL"
    ;;
  production)
    prefix="PRODUCTION"
    ;;
  *)
    echo "Unsupported profile: $profile" >&2
    exit 1
    ;;
esac

has_required_keys() {
  local missing=0
  for key in "${required_keys[@]}"; do
    if [ -z "${!key:-}" ]; then
      missing=1
      break
    fi
  done
  return $missing
}

shell_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

print_exports() {
  for key in "${required_keys[@]}"; do
    printf 'export %s=%s\n' "$key" "$(shell_quote "${!key}")"
  done

  if [ -n "${INFISICAL_SITE_URL:-}" ]; then
    printf 'export INFISICAL_SITE_URL=%s\n' "$(shell_quote "${INFISICAL_SITE_URL}")"
  fi
}

bootstrap_file="${TUNEAV_INFISICAL_BOOTSTRAP_FILE:-${INFISICAL_BOOTSTRAP_FILE:-$repo_root/.infisical/bootstrap.env}}"

if has_required_keys; then
  print_exports
  exit 0
fi

if [ -f "$bootstrap_file" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$bootstrap_file"
  set +a

  for key in "${required_keys[@]}"; do
    prefixed_key="${prefix}_${key}"
    if [ -n "${!prefixed_key:-}" ]; then
      export "$key"="${!prefixed_key}"
    fi
  done

  site_url_key="${prefix}_INFISICAL_SITE_URL"
  if [ -n "${!site_url_key:-}" ]; then
    export INFISICAL_SITE_URL="${!site_url_key}"
  fi

  if has_required_keys; then
    print_exports
    exit 0
  fi
fi

echo "Unable to resolve Infisical bootstrap env for profile '$profile'." >&2
echo "Expected ambient INFISICAL_* vars or $bootstrap_file." >&2
exit 1
