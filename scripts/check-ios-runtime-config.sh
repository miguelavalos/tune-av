#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name=""
configuration="Debug"
destination_args=(-destination "generic/platform=iOS")

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-ios-runtime-config.sh --env dev|prod [--configuration Debug|Release] [--device <UDID>]

Validates the effective Xcode build settings for Tune AV without printing
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
    --device)
      destination_args=(-destination "id=${2:-}")
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

show_settings_args=(
  -project "$repo_root/apps/ios/TuneAV.xcodeproj"
  -scheme TuneAV
  -configuration "$configuration"
)

if [ "${#destination_args[@]}" -gt 0 ]; then
  show_settings_args+=("${destination_args[@]}")
fi

xcodebuild "${show_settings_args[@]}" -showBuildSettings > "$settings_file"

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
management_url="$(setting ACCOUNTAV_MANAGEMENT_URL)"
publishable_key="$(setting ACCOUNTAV_PUBLISHABLE_KEY)"
listening_analytics_uploads="$(setting TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS)"
delete_account_url="$(setting TUNEAV_DELETE_ACCOUNT_URL)"
terms_url="$(setting TUNEAV_TERMS_URL)"
privacy_url="$(setting TUNEAV_PRIVACY_URL)"
open_source_url="$(setting TUNEAV_OPEN_SOURCE_URL)"
development_team="$(setting DEVELOPMENT_TEAM)"

for item in \
  "PRODUCT_BUNDLE_IDENTIFIER:$product_bundle_identifier" \
  "TUNEAV_BUNDLE_IDENTIFIER:$tuneav_bundle_identifier" \
  "ACCOUNTAV_API_BASE_URL:$api_base_url" \
  "TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS:$listening_analytics_uploads" \
  "ACCOUNTAV_MANAGEMENT_URL:$management_url" \
  "ACCOUNTAV_PUBLISHABLE_KEY:$publishable_key" \
  "TUNEAV_DELETE_ACCOUNT_URL:$delete_account_url" \
  "TUNEAV_TERMS_URL:$terms_url" \
  "TUNEAV_PRIVACY_URL:$privacy_url" \
  "TUNEAV_OPEN_SOURCE_URL:$open_source_url"; do
  require_present "${item%%:*}" "${item#*:}"
done

if [ "$env_name" = "prod" ]; then
  [ "$product_bundle_identifier" = "com.avalsys.tuneav" ] || fail "prod bundle must be com.avalsys.tuneav, got $product_bundle_identifier"
  [ "$tuneav_bundle_identifier" = "com.avalsys.tuneav" ] || fail "prod TUNEAV_BUNDLE_IDENTIFIER must be com.avalsys.tuneav"
  [ "$api_base_url" = "https://api-account-av.avalsys.com" ] || fail "prod API URL mismatch: $api_base_url"
  [ "$management_url" = "https://account-av.avalsys.com" ] || fail "prod management URL mismatch: $management_url"
  [ "$listening_analytics_uploads" = "1" ] || fail "prod listening analytics uploads must be enabled after signed-in backend smoke and App Privacy update"
  [[ "$publishable_key" == pk_live_* ]] || fail "prod publishable key must be pk_live"
  if printf '%s\n%s\n%s\n' "$product_bundle_identifier" "$api_base_url" "$management_url" | rg -q 'preview|127\.0\.0\.1|localhost|\.dev'; then
    fail "prod settings contain preview/local/dev values"
  fi
else
  [ "$product_bundle_identifier" = "com.avalsys.tuneav.dev" ] || fail "dev bundle must be com.avalsys.tuneav.dev, got $product_bundle_identifier"
  [ "$tuneav_bundle_identifier" = "com.avalsys.tuneav.dev" ] || fail "dev TUNEAV_BUNDLE_IDENTIFIER must be com.avalsys.tuneav.dev"
  [ "$api_base_url" = "https://api-account-av-preview.avalsys.com" ] || fail "dev API URL mismatch: $api_base_url"
  [ "$management_url" = "https://account-av-preview.avalsys.com" ] || fail "dev management URL mismatch: $management_url"
  [[ "$listening_analytics_uploads" == "0" || "$listening_analytics_uploads" == "1" ]] || fail "dev TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS must be 0 or 1"
  [[ "$publishable_key" == pk_test_* || "$publishable_key" == pk_live_* ]] || fail "dev publishable key has unexpected prefix"
fi

for url in "$api_base_url" "$management_url" "$delete_account_url" "$terms_url" "$privacy_url" "$open_source_url"; do
  [[ "$url" == https://* ]] || fail "URL did not resolve as https://*: $url"
done

redacted_key=""
if [ -n "$publishable_key" ]; then
  redacted_key="${publishable_key:0:8}...${#publishable_key}"
fi

cat <<EOF
Tune AV iOS runtime config ($env_name)
  configuration: $configuration
  product bundle: $product_bundle_identifier
  tune bundle: $tuneav_bundle_identifier
  development team: ${development_team:-unknown}
  Account AV API: $api_base_url
  Account AV management: $management_url
  publishable key: $redacted_key
  delete account: $delete_account_url
  terms: $terms_url
  privacy: $privacy_url
EOF

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Runtime config check passed."
