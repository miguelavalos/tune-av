#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-local}"
configuration="${2:-Debug}"

case "$profile" in
  local)
    expected_bundle_identifier="com.avalsys.tuneav.dev"
    expected_key_prefix="pk_test_"
    expected_api_base_url="http://127.0.0.1:8788"
    expected_management_host="account-av-preview.avalsys.com"
    ;;
  production)
    expected_bundle_identifier="com.avalsys.tuneav"
    expected_key_prefix="pk_live_"
    expected_api_base_url="https://api-account-av.avalsys.com"
    expected_management_host="account-av.avalsys.com"
    configuration="Release"
    ;;
  *)
    echo "Usage: $0 local|production [Debug|Release]" >&2
    exit 2
    ;;
esac

local_config="$repo_root/apps/ios/Config/Local.xcconfig"
if [ ! -f "$local_config" ]; then
  echo "Missing $local_config. Run bun run ios:config or bun run ios:config:production first." >&2
  exit 1
fi

settings="$(
  xcodebuild \
    -project "$repo_root/apps/ios/TuneAV.xcodeproj" \
    -scheme TuneAV \
    -configuration "$configuration" \
    -destination 'generic/platform=iOS Simulator' \
    -showBuildSettings 2>/dev/null
)"

setting_value() {
  local key="$1"
  printf '%s\n' "$settings" \
    | awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { value=$2 } END { print value }'
}

failures=0

expect_value() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if [ "$actual" != "$expected" ]; then
    printf 'Mismatch: %s\n  expected: %s\n  actual:   %s\n' "$label" "$expected" "${actual:-<empty>}" >&2
    failures=$((failures + 1))
  fi
}

expect_prefix() {
  local label="$1"
  local actual="$2"
  local expected_prefix="$3"

  if [[ "$actual" != "$expected_prefix"* ]]; then
    printf 'Mismatch: %s must start with %s. Actual value is hidden.\n' "$label" "$expected_prefix" >&2
    failures=$((failures + 1))
  fi
}

expect_value "PRODUCT_BUNDLE_IDENTIFIER" "$(setting_value PRODUCT_BUNDLE_IDENTIFIER)" "$expected_bundle_identifier"
expect_prefix "ACCOUNTAV_PUBLISHABLE_KEY" "$(setting_value ACCOUNTAV_PUBLISHABLE_KEY)" "$expected_key_prefix"
expect_value "ACCOUNTAV_API_BASE_URL" "$(setting_value ACCOUNTAV_API_BASE_URL)" "$expected_api_base_url"

management_url="$(setting_value ACCOUNTAV_MANAGEMENT_URL)"
if [[ "$management_url" != *"$expected_management_host"* ]]; then
  printf 'Mismatch: ACCOUNTAV_MANAGEMENT_URL must point at %s. Actual: %s\n' "$expected_management_host" "${management_url:-<empty>}" >&2
  failures=$((failures + 1))
fi

development_team="$(setting_value DEVELOPMENT_TEAM)"
if [ -z "$development_team" ] || [ "$development_team" = '$(inherited)' ]; then
  printf 'Mismatch: DEVELOPMENT_TEAM is not resolved. Actual: %s\n' "${development_team:-<empty>}" >&2
  failures=$((failures + 1))
fi

if [ "$(setting_value CODE_SIGN_ENTITLEMENTS)" != "TuneAV/App/TuneAV.entitlements" ]; then
  printf 'Mismatch: CODE_SIGN_ENTITLEMENTS is not TuneAV/App/TuneAV.entitlements.\n' >&2
  failures=$((failures + 1))
fi

if ! plutil -extract keychain-access-groups raw "$repo_root/apps/ios/TuneAV/App/TuneAV.entitlements" >/dev/null 2>&1; then
  printf 'Mismatch: TuneAV.entitlements must include keychain-access-groups for Clerk native auth.\n' >&2
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

printf 'Tune AV iOS %s runtime config preflight passed.\n' "$profile"
