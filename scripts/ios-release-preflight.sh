#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
with_archive=0
check_urls=1
archive_path=""
derived_data_path=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/ios-release-preflight.sh [--with-archive] [--archive <TuneAV.xcarchive>]
    [--derived-data <path>] [--skip-url-check]

Runs the local Tune AV iOS release preflight:
- iOS release config hygiene;
- iOS hardcoded sensitive config hygiene;
- iOS platform security gate;
- iOS network privacy gate;
- iOS release privacy gate;
- optional archive build plus strict archive privacy evidence, Sentry dSYM repair,
  and app-size gates.

Generate apps/ios/Config/Local.xcconfig for production before running:
  vp run ios:config:prod
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-archive)
      with_archive=1
      shift
      ;;
    --archive)
      archive_path="${2:-}"
      with_archive=1
      shift 2
      ;;
    --derived-data)
      derived_data_path="${2:-}"
      shift 2
      ;;
    --skip-url-check)
      check_urls=0
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

cd "$repo_root"

run_step() {
  local label="$1"
  shift

  echo
  echo "==> $label"
  "$@"
}

run_step "iOS release config hygiene" scripts/check-ios-release-config-hygiene.sh --env prod --configuration Release
run_step "iOS hardcoded sensitive config hygiene" node scripts/check-ios-hardcoded-sensitive-config.mjs
run_step "iOS platform security gate" node scripts/check-ios-platform-security.mjs
run_step "iOS network privacy gate" scripts/check-ios-network-privacy.sh
if [ "$check_urls" -eq 1 ]; then
  run_step "iOS release privacy gate" scripts/check-ios-privacy-release-gate.sh --env prod --configuration Release --check-urls
else
  run_step "iOS release privacy gate" scripts/check-ios-privacy-release-gate.sh --env prod --configuration Release
fi

if [ "$with_archive" -eq 1 ]; then
  cleanup_dir=""
  if [ -z "$archive_path" ]; then
    cleanup_dir="$(mktemp -d)"
    archive_path="$cleanup_dir/TuneAV.xcarchive"
  fi
  if [ -z "$derived_data_path" ]; then
    derived_data_path="${cleanup_dir:-$(mktemp -d)}/DerivedData"
  fi

  if [ ! -d "$archive_path" ]; then
    run_step "Build unsigned Release archive" \
      xcodebuild archive \
        -project apps/ios/TuneAV.xcodeproj \
        -scheme TuneAV \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath "$archive_path" \
        -derivedDataPath "$derived_data_path" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        SKIP_INSTALL=NO
  fi

  if [ "$check_urls" -eq 1 ]; then
    run_step "Strict archive privacy evidence gate" \
      scripts/check-ios-privacy-release-gate.sh \
        --env prod \
        --configuration Release \
        --archive "$archive_path" \
        --require-archive \
        --check-urls
  else
    run_step "Strict archive privacy evidence gate" \
      scripts/check-ios-privacy-release-gate.sh \
        --env prod \
        --configuration Release \
        --archive "$archive_path" \
        --require-archive
  fi

  archive_app_path="$archive_path/Products/Applications/TuneAV.app"
  if [ -d "$archive_app_path" ]; then
    run_step "Archive Sentry dSYM repair" \
      scripts/repair-ios-archive-sentry-dsym.sh \
        --archive "$archive_path"

    run_step "Archive app size gate" \
      env \
        TUNEAV_IOS_APP_PATH="$archive_app_path" \
        TUNEAV_IOS_SIZE_REPORT_PATH="$repo_root/.derived-data/release-preflight/app-size.md" \
        scripts/report-ios-app-size.sh
  else
    echo "FAIL archive app bundle is missing: $archive_app_path" >&2
    exit 1
  fi

  if [ -n "$cleanup_dir" ]; then
    rm -rf "$cleanup_dir"
  fi
fi

echo
echo "iOS release preflight passed."
