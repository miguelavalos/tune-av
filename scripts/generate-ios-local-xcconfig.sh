#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$repo_root/../.." && pwd)"
suite_root="${AVALSYS_SUITE_DIR:-$workspace_root/private/avalsys-suite}"
output_path="$repo_root/apps/ios/Config/Local.xcconfig"
env_name=""
stdout_only=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/generate-ios-local-xcconfig.sh --env dev|prod [--stdout]

Generates apps/ios/Config/Local.xcconfig from the private Infisical/Varlock
configuration. The output file is gitignored and must not be committed.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      env_name="${2:-}"
      shift 2
      ;;
    --stdout)
      stdout_only=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$env_name" != "dev" ] && [ "$env_name" != "prod" ]; then
  echo "--env must be dev or prod." >&2
  exit 2
fi

if [ ! -d "$suite_root" ]; then
  echo "Private avalsys suite repo not found: $suite_root" >&2
  echo "Set AVALSYS_SUITE_DIR if it lives somewhere else." >&2
  exit 1
fi

varlock_bin="$suite_root/node_modules/.bin/varlock"
if [ ! -x "$varlock_bin" ]; then
  echo "varlock CLI is required at $varlock_bin. Run bun install in $suite_root." >&2
  exit 1
fi

profile="local"
bundle_identifier="com.avalsys.tuneav.dev"

if [ "$env_name" = "prod" ]; then
  profile="production"
  bundle_identifier="com.avalsys.tuneav"
fi

eval "$("$suite_root/scripts/resolve-infisical-bootstrap-env.sh" "$profile")"

publishable_key="$("$varlock_bin" printenv --path "$suite_root/apps/account-av" VITE_ACCOUNTAV_PUBLISHABLE_KEY)"
if [ -z "$publishable_key" ]; then
  echo "Missing VITE_ACCOUNTAV_PUBLISHABLE_KEY for profile $profile." >&2
  exit 1
fi

read_optional_config() {
  local name="$1"
  local value="${!name:-}"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi

  "$varlock_bin" printenv --path "$suite_root/services/api" "$name" 2>/dev/null || true
}

read_required_config() {
  local name="$1"
  local value

  value="$(read_optional_config "$name")"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi

  echo "Missing $name for $profile profile." >&2
  exit 1
}

read_support_base_url() {
  local value="${SUPPORTAV_BASE_URL:-}"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi

  value="$("$varlock_bin" printenv --path "$suite_root/apps/support-av" SUPPORTAV_BASE_URL 2>/dev/null || true)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi

  if [ "$env_name" = "prod" ]; then
    printf '%s' "https://support-av.avalsys.com"
  else
    printf '%s' "https://support-av-preview.avalsys.com"
  fi
}

api_base_url="${ACCOUNTAV_API_BASE_URL:-${VITE_ACCOUNTAV_API_BASE_URL:-}}"
if [ -z "$api_base_url" ]; then
  api_base_url="$(read_optional_config ACCOUNTAV_API_BASE_URL)"
fi
if [ -z "$api_base_url" ]; then
  api_base_url="$("$varlock_bin" printenv --path "$suite_root/apps/account-av" VITE_ACCOUNTAV_API_BASE_URL 2>/dev/null || true)"
fi
if [ "$env_name" = "prod" ] && printf '%s' "$api_base_url" | rg -q '127\.0\.0\.1|localhost|preview|\.dev'; then
  api_base_url="$(read_optional_config ACCOUNTAV_API_BASE_URL)"
fi
if [ -z "$api_base_url" ]; then
  echo "Missing ACCOUNTAV_API_BASE_URL or VITE_ACCOUNTAV_API_BASE_URL for profile $profile." >&2
  exit 1
fi
if [ "$env_name" = "prod" ] && printf '%s' "$api_base_url" | rg -q '127\.0\.0\.1|localhost|preview|\.dev'; then
  echo "Production ACCOUNTAV_API_BASE_URL must be provided by private config or the environment." >&2
  exit 1
fi
management_url="$(read_optional_config ACCOUNTAV_MANAGEMENT_URL)"
if [ -z "$management_url" ]; then
  management_url="$(node -e '
const input = process.argv[1];
try {
  const url = new URL(input);
  url.hostname = url.hostname.replace(/^api-/, "");
  url.pathname = "";
  url.search = "";
  url.hash = "";
  console.log(url.toString().replace(/\/$/, ""));
} catch {
  process.exit(1);
}
' "$api_base_url")"
fi
development_team="$(read_optional_config AVALSYS_APPLE_DEVELOPMENT_TEAM)"
if [ -z "$development_team" ]; then
  development_team="\$(inherited)"
fi
if [ "$development_team" = "346677S99H" ]; then
  echo "Warning: replacing stale non-Avalsys Apple team 346677S99H with 935PM55U6R." >&2
  development_team="935PM55U6R"
fi
keychain_service="$(read_optional_config ACCOUNTAV_KEYCHAIN_SERVICE)"
keychain_access_group="$(read_optional_config ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)"
if [ -z "$keychain_access_group" ] || [ "$keychain_access_group" = "\$(inherited)" ]; then
  keychain_access_group="935PM55U6R.$bundle_identifier"
fi
premium_product_ids="${TUNEAV_PREMIUM_PRODUCT_IDS:-tuneav_pro_monthly}"
support_email="${SUPPORT_EMAIL_TO:-support@avalsys.com}"
support_base_url="$(read_support_base_url)"
revenuecat_public_api_key="$(read_required_config TUNEAV_REVENUECAT_PUBLIC_API_KEY)"
revenuecat_offering_id="$(read_required_config TUNEAV_REVENUECAT_OFFERING_ID)"
revenuecat_monthly_package_id="$(read_required_config TUNEAV_REVENUECAT_MONTHLY_PACKAGE_ID)"
tuneav_convex_url="$(read_required_config TUNEAV_CONVEX_URL)"
tuneav_ios_sentry_dsn="$(read_optional_config TUNEAV_IOS_SENTRY_DSN)"
if [ "$env_name" = "prod" ]; then
  listening_analytics_uploads="${TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS:-1}"
else
  listening_analytics_uploads="${TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS:-1}"
fi

if [[ "$revenuecat_public_api_key" != appl_* ]]; then
  echo "TUNEAV_REVENUECAT_PUBLIC_API_KEY must be a RevenueCat public app key with appl_ prefix." >&2
  exit 1
fi
if [[ "$revenuecat_public_api_key" == sk_* ]]; then
  echo "TUNEAV_REVENUECAT_PUBLIC_API_KEY must not be a RevenueCat secret key." >&2
  exit 1
fi
if [ -z "$revenuecat_offering_id" ]; then
  echo "TUNEAV_REVENUECAT_OFFERING_ID must not be empty." >&2
  exit 1
fi
if [ -z "$revenuecat_monthly_package_id" ]; then
  echo "TUNEAV_REVENUECAT_MONTHLY_PACKAGE_ID must not be empty." >&2
  exit 1
fi
case "$tuneav_convex_url" in
  https://*.convex.cloud) ;;
  *) echo "TUNEAV_CONVEX_URL must be a Convex cloud URL." >&2; exit 1 ;;
esac

escape_xcconfig_url() {
  printf '%s' "$1" | sed 's#/#$(XCCONFIG_SLASH)#g'
}

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
content="$(cat <<EOF
// GENERATED by scripts/generate-ios-local-xcconfig.sh --env $env_name
// Generated at $generated_at
// Do not edit manually. Regenerate when switching dev/prod.
XCCONFIG_SLASH = /
TUNEAV_CONFIG_ENVIRONMENT = $env_name
TUNEAV_BUNDLE_IDENTIFIER = $bundle_identifier
AVALSYS_APPLE_DEVELOPMENT_TEAM = $development_team
ACCOUNTAV_PUBLISHABLE_KEY = $publishable_key
ACCOUNTAV_KEYCHAIN_SERVICE = $keychain_service
ACCOUNTAV_KEYCHAIN_ACCESS_GROUP = $keychain_access_group
TUNEAV_PREMIUM_PRODUCT_IDS = $premium_product_ids
SUPPORT_EMAIL_TO = $support_email
SUPPORTAV_BASE_URL = $(escape_xcconfig_url "$support_base_url")
ACCOUNTAV_API_BASE_URL = $(escape_xcconfig_url "$api_base_url")
TUNEAV_CONVEX_URL = $(escape_xcconfig_url "$tuneav_convex_url")
TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS = $listening_analytics_uploads
ACCOUNTAV_MANAGEMENT_URL = $(escape_xcconfig_url "$management_url")
TUNEAV_DELETE_ACCOUNT_URL = $(escape_xcconfig_url "https://tune-av.avalsys.com/delete-account")
TUNEAV_TERMS_URL = $(escape_xcconfig_url "https://tune-av.avalsys.com/terms")
TUNEAV_PRIVACY_URL = $(escape_xcconfig_url "https://tune-av.avalsys.com/privacy")
TUNEAV_OPEN_SOURCE_URL = $(escape_xcconfig_url "https://github.com/miguelavalos/tune-av")
TUNEAV_REVENUECAT_PUBLIC_API_KEY = $revenuecat_public_api_key
TUNEAV_REVENUECAT_OFFERING_ID = $revenuecat_offering_id
TUNEAV_REVENUECAT_MONTHLY_PACKAGE_ID = $revenuecat_monthly_package_id
TUNEAV_IOS_SENTRY_DSN = $(escape_xcconfig_url "$tuneav_ios_sentry_dsn")
EOF
)"

if [ "$stdout_only" -eq 1 ]; then
  printf '%s\n' "$content"
else
  umask 077
  mkdir -p "$(dirname "$output_path")"
  printf '%s\n' "$content" > "$output_path"
  echo "Generated $output_path for $env_name."
fi
