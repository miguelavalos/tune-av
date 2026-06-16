#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name=""
configuration="Release"
destination_args=(-destination "platform=macOS")

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-macos-runtime-config.sh --env dev|prod [--configuration Debug|Release]

Validates the effective Xcode build settings for Tune AV macOS without printing
secret values. This checks what Xcode will actually compile, not just the raw
Local.xcconfig file.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env)
      env_name="${2:-}"
      shift 2
      ;;
    --configuration)
      configuration="${2:-}"
      shift 2
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

settings_file="$(mktemp)"
trap 'rm -f "$settings_file"' EXIT

xcodebuild \
  -project "$repo_root/apps/macos/TuneAVMac.xcodeproj" \
  -scheme TuneAVMac \
  -configuration "$configuration" \
  "${destination_args[@]}" \
  -showBuildSettings > "$settings_file"

setting() {
  local key="$1"
  awk -F= -v wanted="$key" '
    $1 ~ "^[[:space:]]*" wanted "[[:space:]]*$" {
      value=$2
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$settings_file"
}

failures=0
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_present() {
  local key="$1"
  local value="$2"
  if [ -z "$value" ] || [ "$value" = '$(inherited)' ]; then
    fail "$key is missing"
  fi
}

product_bundle_identifier="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
tuneav_bundle_identifier="$(setting TUNEAV_BUNDLE_IDENTIFIER)"
api_base_url="$(setting ACCOUNTAV_API_BASE_URL)"
tune_api_base_url="$(setting TUNEAV_API_BASE_URL)"
management_url="$(setting ACCOUNTAV_MANAGEMENT_URL)"
tuneav_convex_url="$(setting TUNEAV_CONVEX_URL)"
publishable_key="$(setting ACCOUNTAV_PUBLISHABLE_KEY)"
keychain_service="$(setting ACCOUNTAV_KEYCHAIN_SERVICE)"
keychain_access_group="$(setting ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)"
support_base_url="$(setting SUPPORTAV_BASE_URL)"
delete_account_url="$(setting TUNEAV_DELETE_ACCOUNT_URL)"
terms_url="$(setting TUNEAV_TERMS_URL)"
privacy_url="$(setting TUNEAV_PRIVACY_URL)"
open_source_url="$(setting TUNEAV_OPEN_SOURCE_URL)"
support_email="$(setting SUPPORT_EMAIL_TO)"
development_team="$(setting DEVELOPMENT_TEAM)"
code_sign_style="$(setting CODE_SIGN_STYLE)"
enable_hardened_runtime="$(setting ENABLE_HARDENED_RUNTIME)"
enable_app_sandbox="$(setting ENABLE_APP_SANDBOX)"

for item in \
  "PRODUCT_BUNDLE_IDENTIFIER:$product_bundle_identifier" \
  "TUNEAV_BUNDLE_IDENTIFIER:$tuneav_bundle_identifier" \
  "ACCOUNTAV_API_BASE_URL:$api_base_url" \
  "TUNEAV_API_BASE_URL:$tune_api_base_url" \
  "ACCOUNTAV_MANAGEMENT_URL:$management_url" \
  "TUNEAV_CONVEX_URL:$tuneav_convex_url" \
  "ACCOUNTAV_PUBLISHABLE_KEY:$publishable_key" \
  "ACCOUNTAV_KEYCHAIN_SERVICE:$keychain_service" \
  "ACCOUNTAV_KEYCHAIN_ACCESS_GROUP:$keychain_access_group" \
  "TUNEAV_DELETE_ACCOUNT_URL:$delete_account_url" \
  "TUNEAV_TERMS_URL:$terms_url" \
  "TUNEAV_PRIVACY_URL:$privacy_url" \
  "TUNEAV_OPEN_SOURCE_URL:$open_source_url" \
  "SUPPORT_EMAIL_TO:$support_email"; do
  require_present "${item%%:*}" "${item#*:}"
done

[ "$code_sign_style" = "Automatic" ] || fail "CODE_SIGN_STYLE must stay Automatic, got $code_sign_style"
[ "$enable_hardened_runtime" = "YES" ] || fail "ENABLE_HARDENED_RUNTIME must stay YES"
[ "$enable_app_sandbox" = "YES" ] || fail "ENABLE_APP_SANDBOX must stay YES"

if [ "$env_name" = "prod" ]; then
  [ "$product_bundle_identifier" = "com.avalsys.tuneav" ] || fail "prod bundle must be com.avalsys.tuneav, got $product_bundle_identifier"
  [ "$tuneav_bundle_identifier" = "com.avalsys.tuneav" ] || fail "prod TUNEAV_BUNDLE_IDENTIFIER must be com.avalsys.tuneav"
  [ "$keychain_service" = "com.avalsys.tuneav.account.v2" ] || fail "prod ACCOUNTAV_KEYCHAIN_SERVICE must be com.avalsys.tuneav.account.v2, got $keychain_service"
  [ "$keychain_access_group" = "935PM55U6R.com.avalsys.tuneav" ] || fail "prod ACCOUNTAV_KEYCHAIN_ACCESS_GROUP must be 935PM55U6R.com.avalsys.tuneav, got $keychain_access_group"
  [[ "$publishable_key" == pk_live_* ]] || fail "prod publishable key must be pk_live"
  if printf '%s\n%s\n%s\n%s\n' "$product_bundle_identifier" "$api_base_url" "$tune_api_base_url" "$management_url" | rg -q 'preview|127\.0\.0\.1|localhost|\.dev'; then
    fail "prod settings contain preview/local/dev values"
  fi
  if [ -n "$development_team" ] && [ "$development_team" != '$(inherited)' ]; then
    [[ "$development_team" =~ ^[A-Z0-9]{10}$ ]] || fail "DEVELOPMENT_TEAM must look like a 10-character Apple team ID"
  else
    fail "DEVELOPMENT_TEAM is missing for prod"
  fi
else
  [ "$product_bundle_identifier" = "com.avalsys.tuneav.mac.dev" ] || fail "dev bundle must be com.avalsys.tuneav.mac.dev, got $product_bundle_identifier"
  [ "$tuneav_bundle_identifier" = "com.avalsys.tuneav.mac.dev" ] || fail "dev TUNEAV_BUNDLE_IDENTIFIER must be com.avalsys.tuneav.mac.dev"
  [ "$keychain_service" = "com.avalsys.tuneav.mac.dev.account.v2" ] || fail "dev ACCOUNTAV_KEYCHAIN_SERVICE must be com.avalsys.tuneav.mac.dev.account.v2, got $keychain_service"
  [ "$keychain_access_group" = "935PM55U6R.com.avalsys.tuneav.mac.dev" ] || fail "dev ACCOUNTAV_KEYCHAIN_ACCESS_GROUP must be 935PM55U6R.com.avalsys.tuneav.mac.dev, got $keychain_access_group"
  [[ "$publishable_key" == pk_test_* || "$publishable_key" == pk_live_* ]] || fail "dev publishable key has unexpected prefix"
fi

allow_https_or_dev_local_url() {
  local name="$1"
  local value="$2"

  if [[ "$value" == https://* ]]; then
    return 0
  fi

  if [ "$env_name" = "dev" ]; then
    case "$value" in
      http://127.0.0.1:*|http://localhost:*) return 0 ;;
    esac
  fi

  fail "$name did not resolve as https://* or a dev localhost URL: $value"
}

allow_https_or_dev_local_url ACCOUNTAV_API_BASE_URL "$api_base_url"
allow_https_or_dev_local_url TUNEAV_API_BASE_URL "$tune_api_base_url"
allow_https_or_dev_local_url ACCOUNTAV_MANAGEMENT_URL "$management_url"

for url in "$delete_account_url" "$terms_url" "$privacy_url" "$open_source_url"; do
  [[ "$url" == https://* ]] || fail "URL did not resolve as https://*: $url"
done
[[ "$tuneav_convex_url" == https://*.convex.cloud ]] || fail "TUNEAV_CONVEX_URL must be a Convex cloud URL"
if [ -n "$support_base_url" ] && [ "$support_base_url" != '$(inherited)' ]; then
  [[ "$support_base_url" == https://* ]] || fail "URL did not resolve as https://*: $support_base_url"
fi
[[ "$support_email" == *"@"* ]] || fail "SUPPORT_EMAIL_TO must look like an email address"

redacted_key=""
if [ -n "$publishable_key" ]; then
  redacted_key="${publishable_key:0:8}...${#publishable_key}"
fi
redacted_team="unknown"
if [ -n "$development_team" ] && [ "$development_team" != '$(inherited)' ]; then
  redacted_team="${development_team:0:3}...${#development_team}"
elif [ -n "$development_team" ]; then
  redacted_team="$development_team"
fi

cat <<EOF
Tune AV macOS runtime config ($env_name)
  configuration: $configuration
  product bundle: $product_bundle_identifier
  tune bundle: $tuneav_bundle_identifier
  development team: $redacted_team
  code sign style: $code_sign_style
  App Sandbox: $enable_app_sandbox
  Hardened Runtime: $enable_hardened_runtime
  Account AV API: $api_base_url
  Tune AV API: $tune_api_base_url
  Tune AV Convex: $tuneav_convex_url
  Account AV management: $management_url
  Account AV keychain service: $keychain_service
  Account AV keychain access group: $keychain_access_group
  Support AV: ${support_base_url:-email fallback}
  publishable key: $redacted_key
  support email: $support_email
  delete account: $delete_account_url
  terms: $terms_url
  privacy: $privacy_url
  open source: $open_source_url
EOF

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Runtime config check passed."
