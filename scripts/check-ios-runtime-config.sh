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
tune_api_base_url="$(setting TUNEAV_API_BASE_URL)"
tuneav_convex_url="$(setting TUNEAV_CONVEX_URL)"
management_url="$(setting ACCOUNTAV_MANAGEMENT_URL)"
publishable_key="$(setting ACCOUNTAV_PUBLISHABLE_KEY)"
keychain_access_group="$(setting ACCOUNTAV_KEYCHAIN_ACCESS_GROUP)"
support_base_url="$(setting SUPPORTAV_BASE_URL)"
listening_analytics_uploads="$(setting TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS)"
delete_account_url="$(setting TUNEAV_DELETE_ACCOUNT_URL)"
terms_url="$(setting TUNEAV_TERMS_URL)"
privacy_url="$(setting TUNEAV_PRIVACY_URL)"
open_source_url="$(setting TUNEAV_OPEN_SOURCE_URL)"
revenuecat_public_api_key="$(setting TUNEAV_REVENUECAT_PUBLIC_API_KEY)"
revenuecat_offering_id="$(setting TUNEAV_REVENUECAT_OFFERING_ID)"
revenuecat_monthly_package_id="$(setting TUNEAV_REVENUECAT_MONTHLY_PACKAGE_ID)"
development_team="$(setting DEVELOPMENT_TEAM)"

for item in \
  "PRODUCT_BUNDLE_IDENTIFIER:$product_bundle_identifier" \
  "TUNEAV_BUNDLE_IDENTIFIER:$tuneav_bundle_identifier" \
  "ACCOUNTAV_API_BASE_URL:$api_base_url" \
  "TUNEAV_API_BASE_URL:$tune_api_base_url" \
  "TUNEAV_CONVEX_URL:$tuneav_convex_url" \
  "TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS:$listening_analytics_uploads" \
  "ACCOUNTAV_MANAGEMENT_URL:$management_url" \
  "ACCOUNTAV_PUBLISHABLE_KEY:$publishable_key" \
  "ACCOUNTAV_KEYCHAIN_ACCESS_GROUP:$keychain_access_group" \
  "TUNEAV_DELETE_ACCOUNT_URL:$delete_account_url" \
  "TUNEAV_TERMS_URL:$terms_url" \
  "TUNEAV_PRIVACY_URL:$privacy_url" \
  "TUNEAV_OPEN_SOURCE_URL:$open_source_url" \
  "TUNEAV_REVENUECAT_PUBLIC_API_KEY:$revenuecat_public_api_key" \
  "TUNEAV_REVENUECAT_OFFERING_ID:$revenuecat_offering_id" \
  "TUNEAV_REVENUECAT_MONTHLY_PACKAGE_ID:$revenuecat_monthly_package_id"; do
  require_present "${item%%:*}" "${item#*:}"
done

[[ "$revenuecat_public_api_key" == appl_* ]] || fail "TUNEAV_REVENUECAT_PUBLIC_API_KEY must use the RevenueCat public appl_ prefix"
[[ "$revenuecat_public_api_key" != sk_* ]] || fail "TUNEAV_REVENUECAT_PUBLIC_API_KEY must not be a RevenueCat secret key"
[ "$revenuecat_offering_id" = "default" ] || fail "TUNEAV_REVENUECAT_OFFERING_ID must be default, got $revenuecat_offering_id"
[ "$revenuecat_monthly_package_id" = '$rc_monthly' ] || fail "TUNEAV_REVENUECAT_MONTHLY_PACKAGE_ID must be literal \$rc_monthly, got $revenuecat_monthly_package_id"
[[ "$tuneav_convex_url" == https://*.convex.cloud ]] || fail "TUNEAV_CONVEX_URL must be a Convex cloud URL"

if [ "$env_name" = "prod" ]; then
  [ "$product_bundle_identifier" = "com.avalsys.tuneav" ] || fail "prod bundle must be com.avalsys.tuneav, got $product_bundle_identifier"
  [ "$tuneav_bundle_identifier" = "com.avalsys.tuneav" ] || fail "prod TUNEAV_BUNDLE_IDENTIFIER must be com.avalsys.tuneav"
  [ "$keychain_access_group" = "935PM55U6R.com.avalsys.tuneav" ] || fail "prod ACCOUNTAV_KEYCHAIN_ACCESS_GROUP must be 935PM55U6R.com.avalsys.tuneav, got $keychain_access_group"
  [[ "$api_base_url" == https://* ]] || fail "prod API URL must use https"
  [[ "$tune_api_base_url" == https://* ]] || fail "prod Tune API URL must use https"
  [[ "$management_url" == https://* ]] || fail "prod management URL must use https"
  if [ -n "$support_base_url" ] && [ "$support_base_url" != '$(inherited)' ]; then
    [[ "$support_base_url" == https://* ]] || fail "prod support URL must use https"
  fi
  [ "$listening_analytics_uploads" = "1" ] || fail "prod listening analytics uploads must be enabled after signed-in backend smoke and App Privacy update"
  [[ "$publishable_key" == pk_live_* ]] || fail "prod publishable key must be pk_live"
  if printf '%s\n%s\n%s\n%s\n%s\n' "$product_bundle_identifier" "$api_base_url" "$tune_api_base_url" "$tuneav_convex_url" "$management_url" | grep -Eq 'preview|127\.0\.0\.1|localhost|\.dev'; then
    fail "prod settings contain preview/local/dev values"
  fi
else
  [ "$product_bundle_identifier" = "com.avalsys.tuneav.dev" ] || fail "dev bundle must be com.avalsys.tuneav.dev, got $product_bundle_identifier"
  [ "$tuneav_bundle_identifier" = "com.avalsys.tuneav.dev" ] || fail "dev TUNEAV_BUNDLE_IDENTIFIER must be com.avalsys.tuneav.dev"
  [ "$keychain_access_group" = "935PM55U6R.com.avalsys.tuneav.dev" ] || fail "dev ACCOUNTAV_KEYCHAIN_ACCESS_GROUP must be 935PM55U6R.com.avalsys.tuneav.dev, got $keychain_access_group"
  [[ "$api_base_url" == https://* ]] || fail "dev API URL must use https"
  [[ "$tune_api_base_url" == https://* ]] || fail "dev Tune API URL must use https"
  [[ "$management_url" == https://* ]] || fail "dev management URL must use https"
  [[ "$listening_analytics_uploads" == "0" || "$listening_analytics_uploads" == "1" ]] || fail "dev TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS must be 0 or 1"
  [[ "$publishable_key" == pk_test_* || "$publishable_key" == pk_live_* ]] || fail "dev publishable key has unexpected prefix"
fi

for url in "$api_base_url" "$tune_api_base_url" "$management_url" "$delete_account_url" "$terms_url" "$privacy_url" "$open_source_url"; do
  [[ "$url" == https://* ]] || fail "URL did not resolve as https://*: $url"
done
if [ -n "$support_base_url" ] && [ "$support_base_url" != '$(inherited)' ]; then
  [[ "$support_base_url" == https://* ]] || fail "URL did not resolve as https://*: $support_base_url"
fi

redacted_key=""
if [ -n "$publishable_key" ]; then
  redacted_key="${publishable_key:0:8}...${#publishable_key}"
fi
redacted_revenuecat_key=""
if [ -n "$revenuecat_public_api_key" ]; then
  redacted_revenuecat_key="${revenuecat_public_api_key:0:8}...${#revenuecat_public_api_key}"
fi
redacted_development_team="unknown"
if [ -n "$development_team" ] && [ "$development_team" != '$(inherited)' ]; then
  redacted_development_team="${development_team:0:3}...${#development_team}"
elif [ -n "$development_team" ]; then
  redacted_development_team="$development_team"
fi

cat <<EOF
Tune AV iOS runtime config ($env_name)
  configuration: $configuration
  product bundle: $product_bundle_identifier
  tune bundle: $tuneav_bundle_identifier
  development team: $redacted_development_team
  Account AV API: $api_base_url
  Tune AV API: $tune_api_base_url
  Tune AV Convex: $tuneav_convex_url
  Account AV management: $management_url
  Account AV keychain access group: $keychain_access_group
  Support AV: ${support_base_url:-email fallback}
  publishable key: $redacted_key
  RevenueCat key: $redacted_revenuecat_key
  RevenueCat offering: $revenuecat_offering_id
  RevenueCat monthly package: $revenuecat_monthly_package_id
  delete account: $delete_account_url
  terms: $terms_url
  privacy: $privacy_url
EOF

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "Runtime config check passed."
