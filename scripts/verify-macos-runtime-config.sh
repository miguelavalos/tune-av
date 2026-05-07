#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-local}"
configuration="${2:-Debug}"

case "$profile" in
  local)
    expected_bundle_identifier="com.avalsys.tuneav.mac.dev"
    expected_key_prefix="pk_test_"
    expected_api_base_url="http://127.0.0.1:8788"
    expected_management_host="account-av-preview.avalsys.com"
    ;;
  production)
    expected_bundle_identifier="com.avalsys.tuneav.mac"
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

local_config="$repo_root/apps/macos/Config/Local.xcconfig"
if [ ! -f "$local_config" ]; then
  echo "Missing $local_config. Run bun run macos:config or bun run macos:config:production first." >&2
  exit 1
fi

settings="$(
  xcodebuild \
    -project "$repo_root/apps/macos/TuneAVMac.xcodeproj" \
    -scheme TuneAVMac \
    -configuration "$configuration" \
    -destination 'platform=macOS' \
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
expect_value "CODE_SIGN_ENTITLEMENTS" "$(setting_value CODE_SIGN_ENTITLEMENTS)" "Supporting/TuneAVMac.entitlements"
expect_value "ENABLE_APP_SANDBOX" "$(setting_value ENABLE_APP_SANDBOX)" "YES"
expect_value "ENABLE_HARDENED_RUNTIME" "$(setting_value ENABLE_HARDENED_RUNTIME)" "YES"

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

if ! plutil -p "$repo_root/apps/macos/Supporting/TuneAVMac.entitlements" | grep -q '"com.apple.security.app-sandbox" => true'; then
  printf 'Mismatch: TuneAVMac.entitlements must enable the App Sandbox for Mac App Store distribution.\n' >&2
  failures=$((failures + 1))
fi

if ! plutil -p "$repo_root/apps/macos/Supporting/TuneAVMac.entitlements" | grep -q '"com.apple.security.network.client" => true'; then
  printf 'Mismatch: TuneAVMac.entitlements must allow outbound network client access for radio streams and Account AV.\n' >&2
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

printf 'Tune AV macOS %s runtime config preflight passed.\n' "$profile"
