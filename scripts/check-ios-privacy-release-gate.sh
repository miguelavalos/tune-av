#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name="prod"
configuration="Release"
archive_path=""
derived_data_path=""
check_urls=0
require_archive=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/check-ios-privacy-release-gate.sh [--env dev|prod] [--configuration Debug|Release]
    [--archive <TuneAV.xcarchive>] [--derived-data <path>] [--check-urls]
    [--require-archive]

Runs the Tune AV iOS privacy release gate without printing secrets:
- validates effective runtime config;
- verifies legal/support URLs are configured, and optionally reachable;
- inventories Swift package SDKs relevant to App Privacy;
- lists PrivacyInfo.xcprivacy manifests from the archive or DerivedData.

Pass --archive for the final App Store archive. Without --archive or
--derived-data this script reports source-level evidence and reminds you that
archive-level SDK privacy evidence is still required before submission.

Pass --require-archive in release/export workflows so submission evidence can
only come from the final .xcarchive, never stale or unrelated DerivedData.
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
    --archive)
      archive_path="${2:-}"
      shift 2
      ;;
    --derived-data)
      derived_data_path="${2:-}"
      shift 2
      ;;
    --check-urls)
      check_urls=1
      shift
      ;;
    --require-archive)
      require_archive=1
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

if [ "$require_archive" -eq 1 ] && [ -z "$archive_path" ]; then
  echo "--require-archive requires --archive <TuneAV.xcarchive>." >&2
  exit 2
fi

failures=0
warnings=0

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

warn() {
  printf 'WARN %s\n' "$1" >&2
  warnings=$((warnings + 1))
}

settings_file="$(mktemp)"
privacy_manifest_file="$(mktemp)"
trap 'rm -f "$settings_file" "$privacy_manifest_file"' EXIT

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

check_url_reachable() {
  local label="$1"
  local url="$2"

  if curl --fail --silent --show-error --location --head --max-time 12 "$url" >/dev/null; then
    printf '  %s: reachable\n' "$label"
    return
  fi

  if curl --fail --silent --show-error --location --max-time 12 --range 0-0 "$url" >/dev/null; then
    printf '  %s: reachable\n' "$label"
    return
  fi

  fail "$label URL is not externally reachable: $url"
}

cd "$repo_root"

if ! node "$repo_root/scripts/check-apple-privacy-manifest.mjs" \
  "$repo_root/apps/ios/TuneAV/App/PrivacyInfo.xcprivacy"; then
  fail "the iOS source privacy manifest is incomplete or invalid"
fi

"$repo_root/scripts/check-ios-runtime-config.sh" --env "$env_name" --configuration "$configuration"

xcodebuild \
  -project "$repo_root/apps/ios/TuneAV.xcodeproj" \
  -scheme TuneAV \
  -configuration "$configuration" \
  -destination "generic/platform=iOS" \
  -showBuildSettings > "$settings_file"

product_bundle_identifier="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
privacy_url="$(setting TUNEAV_PRIVACY_URL)"
terms_url="$(setting TUNEAV_TERMS_URL)"
delete_account_url="$(setting TUNEAV_DELETE_ACCOUNT_URL)"
open_source_url="$(setting TUNEAV_OPEN_SOURCE_URL)"
support_base_url="$(setting SUPPORTAV_BASE_URL)"
analytics_uploads="$(setting TUNEAV_ENABLE_LISTENING_ANALYTICS_UPLOADS)"

echo
echo "Tune AV privacy release gate"
echo "  env: $env_name"
echo "  configuration: $configuration"
echo "  bundle: $product_bundle_identifier"
echo "  listening analytics uploads: $analytics_uploads"
echo "  privacy: $privacy_url"
echo "  terms: $terms_url"
echo "  delete account: $delete_account_url"
echo "  open source: $open_source_url"
if [ -n "$support_base_url" ] && [ "$support_base_url" != '$(inherited)' ]; then
  echo "  support: $support_base_url"
else
  echo "  support: email fallback"
fi

if [ "$check_urls" -eq 1 ]; then
  echo
  echo "External URL reachability"
  check_url_reachable "privacy" "$privacy_url"
  check_url_reachable "terms" "$terms_url"
  check_url_reachable "delete account" "$delete_account_url"
  check_url_reachable "open source" "$open_source_url"
  if [ -n "$support_base_url" ] && [ "$support_base_url" != '$(inherited)' ]; then
    check_url_reachable "support" "$support_base_url"
  fi
else
  warn "external URL reachability was not checked; pass --check-urls for submission evidence"
fi

package_resolved="apps/ios/TuneAV.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

echo
echo "Privacy-relevant Swift package inventory"
if [ ! -f "$package_resolved" ]; then
  fail "Swift Package.resolved is missing at $package_resolved"
else
  sdk_checks=(
    "RevenueCat:purchases-ios-spm|RevenueCat"
    "Clerk:clerk-ios|ClerkKit"
    "PhoneNumberKit:phonenumberkit|PhoneNumberKit"
    "Nuke:nuke|Nuke"
  )
  for sdk_check in "${sdk_checks[@]}"; do
    sdk="${sdk_check%%:*}"
    pattern="${sdk_check#*:}"
    if rg -qi "$pattern" "$package_resolved"; then
      printf '  %s: present\n' "$sdk"
    else
      warn "$sdk was not found in Package.resolved; confirm whether it was removed intentionally"
    fi
  done
fi

search_roots=()
if [ -n "$archive_path" ]; then
  if [ -d "$archive_path" ]; then
    case "$archive_path" in
      *.xcarchive) ;;
      *) fail "archive path must point to a .xcarchive bundle: $archive_path" ;;
    esac
    search_roots+=("$archive_path")
  else
    fail "archive path does not exist: $archive_path"
  fi
fi

if [ "$require_archive" -eq 1 ] && [ -n "$derived_data_path" ]; then
  fail "--derived-data cannot be used with --require-archive; pass the final .xcarchive only"
elif [ -n "$derived_data_path" ]; then
  if [ -d "$derived_data_path" ]; then
    search_roots+=("$derived_data_path")
  else
    fail "derived data path does not exist: $derived_data_path"
  fi
fi

if [ "${#search_roots[@]}" -eq 0 ] && [ "$require_archive" -eq 0 ]; then
  for candidate in \
    "apps/ios/.DerivedData-codex" \
    "apps/ios/.DerivedData-device-release"; do
    if [ -d "$candidate" ]; then
      search_roots+=("$candidate")
    fi
  done

  for candidate in "$HOME"/Library/Developer/Xcode/DerivedData/TuneAV-*; do
    if [ -d "$candidate" ]; then
      search_roots+=("$candidate")
    fi
  done
fi

echo
echo "Privacy manifests"
if [ "${#search_roots[@]}" -eq 0 ]; then
  if [ "$require_archive" -eq 1 ]; then
    fail "no .xcarchive search root found; pass --archive <TuneAV.xcarchive>"
  else
    warn "no archive or DerivedData search root found; archive-level PrivacyInfo.xcprivacy evidence is still required"
  fi
else
  find "${search_roots[@]}" -name PrivacyInfo.xcprivacy -print 2>/dev/null | sort -u > "$privacy_manifest_file"
  if [ -s "$privacy_manifest_file" ]; then
    sed 's/^/  /' "$privacy_manifest_file"
  else
    warn "no PrivacyInfo.xcprivacy files found in selected archive/DerivedData roots"
  fi
fi

if [ -n "$archive_path" ] && [ -s "$privacy_manifest_file" ]; then
  if ! rg -qi "RevenueCat|Purchases" "$privacy_manifest_file"; then
    warn "archive manifest paths do not mention RevenueCat/Purchases; inspect archive package contents manually"
  fi
fi

if [ -n "$archive_path" ] && [ -d "$archive_path" ]; then
  ios_app_manifest="$archive_path/Products/Applications/TuneAV.app/PrivacyInfo.xcprivacy"
  if ! node "$repo_root/scripts/check-apple-privacy-manifest.mjs" "$ios_app_manifest"; then
    fail "the archived iOS app privacy manifest is missing, incomplete, or invalid"
  fi
fi

if [ "$env_name" = "prod" ] && [ "$analytics_uploads" != "1" ]; then
  fail "prod App Privacy gate expects listening analytics uploads enabled and disclosed"
fi

echo
echo "Gate summary: $failures failure(s), $warnings warning(s)."
if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "iOS privacy release gate passed."
