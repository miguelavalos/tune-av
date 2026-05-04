#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile="${1:-local}"
output_mode="${2:-write}"

case "$profile" in
  local)
    bundle_identifier="com.avalsys.tuneav.dev"
    mac_bundle_identifier="com.avalsys.tuneav.mac.dev"
    ;;
  production)
    bundle_identifier="com.avalsys.tuneav"
    mac_bundle_identifier="com.avalsys.tuneav.mac"
    ;;
  *)
    echo "Unsupported profile: $profile" >&2
    exit 1
    ;;
esac

eval "$("$repo_root/scripts/resolve-infisical-bootstrap-env.sh" "$profile")"

varlock_bin="$repo_root/node_modules/.bin/varlock"

if [ ! -x "$varlock_bin" ]; then
  echo "varlock CLI is required. Run 'bun install' in $repo_root." >&2
  exit 1
fi

printenv_value() {
  local key="$1"
  "$varlock_bin" printenv --path "$repo_root/" "$key" 2>/dev/null || true
}

printenv_first_value() {
  local key
  local value
  for key in "$@"; do
    value="$(printenv_value "$key")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return 0
    fi
  done
}

xcodebuild_url_value() {
  local value="$1"
  printf '%s' "$value" | sed 's#//#/$()/#g'
}

account_publishable_key="$(printenv_value ACCOUNTAV_PUBLISHABLE_KEY)"
premium_product_ids="$(printenv_value TUNEAV_PREMIUM_PRODUCT_IDS)"
support_email="$(printenv_value TUNEAV_SUPPORT_EMAIL)"
avaccount_api_base_url="$(printenv_value ACCOUNTAV_API_BASE_URL)"
account_management_url="$(printenv_value ACCOUNTAV_MANAGEMENT_URL)"
terms_url="$(printenv_value TUNEAV_TERMS_URL)"
privacy_url="$(printenv_value TUNEAV_PRIVACY_URL)"
open_source_url="$(printenv_value TUNEAV_OPEN_SOURCE_URL)"
development_team="$(printenv_value AVALSYS_APPLE_DEVELOPMENT_TEAM)"

required_values=(
  account_publishable_key
  premium_product_ids
  support_email
  avaccount_api_base_url
  account_management_url
  terms_url
  privacy_url
)

for value_name in "${required_values[@]}"; do
  if [ -z "${!value_name:-}" ]; then
    echo "Missing required value from Infisical: $value_name" >&2
    exit 1
  fi
done

assert_no_legacy_value() {
  local value_name="$1"
  local value="${!value_name:-}"
  local normalized_value
  local expected_value=""

  normalized_value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -d ' _-')"

  case "$normalized_value" in
    *avtunesys*|*avapps*)
      if [[ "$normalized_value" == *avtunesys* ]]; then
        echo "Legacy radio product value found in Infisical-derived config: $value_name" >&2
      else
        echo "Legacy account platform value found in Infisical-derived config: $value_name" >&2
      fi
      case "$value_name" in
        premium_product_ids)
          expected_value="com.avalsys.tuneav.pro.monthly,com.avalsys.tuneav.pro.yearly"
          ;;
        avaccount_api_base_url)
          expected_value="Use the Account AV API base URL."
          ;;
        account_management_url)
          expected_value="Use the Tune AV account management URL."
          ;;
        terms_url)
          expected_value="Use the Tune AV terms URL."
          ;;
        privacy_url)
          expected_value="Use the Tune AV privacy URL."
          ;;
        open_source_url)
          expected_value="https://github.com/miguelavalos/tune-av"
          ;;
      esac
      if [ -n "$expected_value" ]; then
        echo "Expected: $expected_value" >&2
      fi
      echo "Update this secret before generating native config." >&2
      exit 1
      ;;
  esac
}

legacy_checked_values=(
  premium_product_ids
  avaccount_api_base_url
  account_management_url
  terms_url
  privacy_url
  open_source_url
)

for value_name in "${legacy_checked_values[@]}"; do
  assert_no_legacy_value "$value_name"
done

render_config() {
  local resolved_bundle_identifier="$1"
  cat <<EOF
TUNEAV_BUNDLE_IDENTIFIER = $resolved_bundle_identifier
AVALSYS_APPLE_DEVELOPMENT_TEAM = $development_team
ACCOUNTAV_PUBLISHABLE_KEY = $account_publishable_key
TUNEAV_PREMIUM_PRODUCT_IDS = $premium_product_ids
TUNEAV_SUPPORT_EMAIL = $support_email
ACCOUNTAV_API_BASE_URL = $(xcodebuild_url_value "$avaccount_api_base_url")
ACCOUNTAV_MANAGEMENT_URL = $(xcodebuild_url_value "$account_management_url")
TUNEAV_TERMS_URL = $(xcodebuild_url_value "$terms_url")
TUNEAV_PRIVACY_URL = $(xcodebuild_url_value "$privacy_url")
TUNEAV_OPEN_SOURCE_URL = $(xcodebuild_url_value "$open_source_url")
EOF
}

ios_rendered_config="$(render_config "$bundle_identifier")"
macos_rendered_config="$(render_config "$mac_bundle_identifier")"

ios_target_file="$repo_root/apps/ios/Config/Local.xcconfig"
macos_target_file="$repo_root/apps/macos/TuneAVMac/Config/Local.xcconfig"

case "$output_mode" in
  write)
    umask 077
    mkdir -p "$(dirname "$ios_target_file")" "$(dirname "$macos_target_file")"
    printf '%s\n' "$ios_rendered_config" > "$ios_target_file"
    printf '%s\n' "$macos_rendered_config" > "$macos_target_file"
    echo "Wrote $ios_target_file and $macos_target_file for profile '$profile'."
    ;;
  stdout)
    printf '# %s\n%s\n\n# %s\n%s\n' "$ios_target_file" "$ios_rendered_config" "$macos_target_file" "$macos_rendered_config"
    ;;
  *)
    echo "Unsupported output mode: $output_mode" >&2
    exit 1
    ;;
esac
