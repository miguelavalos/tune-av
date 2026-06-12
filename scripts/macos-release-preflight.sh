#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
with_archive=0
archive_path=""
derived_data_path=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/macos-release-preflight.sh [--with-archive] [--archive <TuneAVMac.xcarchive>]
    [--derived-data <path>]

Runs the local Tune AV macOS release preflight:
- macOS release config hygiene;
- macOS platform security gate;
- optional unsigned Release archive build;
- archive bundle identifier validation.

Generate apps/macos/Config/Local.xcconfig for production before running.
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

run_step "macOS release config hygiene" scripts/check-macos-release-config-hygiene.sh --env prod --configuration Release
run_step "macOS platform security gate" node scripts/check-macos-platform-security.mjs

if [ "$with_archive" -eq 1 ]; then
  cleanup_dir=""
  if [ -z "$archive_path" ]; then
    cleanup_dir="$(mktemp -d)"
    archive_path="$cleanup_dir/TuneAVMac.xcarchive"
  fi
  if [ -z "$derived_data_path" ]; then
    derived_data_path="${cleanup_dir:-$(mktemp -d)}/DerivedData"
  fi

  if [ ! -d "$archive_path" ]; then
    run_step "Build unsigned Release archive" \
      xcodebuild archive \
        -project apps/macos/TuneAVMac.xcodeproj \
        -scheme TuneAVMac \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "$archive_path" \
        -derivedDataPath "$derived_data_path" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        SKIP_INSTALL=NO \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=NO
  fi

  archive_app_path="$archive_path/Products/Applications/Tune AV.app"
  if [ ! -d "$archive_app_path" ]; then
    echo "FAIL archive app bundle is missing: $archive_app_path" >&2
    exit 1
  fi

  archive_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$archive_path/Info.plist" 2>/dev/null || true)"
  if [ -z "$archive_bundle_id" ]; then
    archive_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$archive_app_path/Contents/Info.plist" 2>/dev/null || true)"
  fi
  if [ "$archive_bundle_id" != "com.avalsys.tuneav.mac" ]; then
    echo "FAIL archive bundle identifier must be com.avalsys.tuneav.mac, got: ${archive_bundle_id:-<missing>}" >&2
    exit 1
  fi

  app_binary="$archive_app_path/Contents/MacOS/Tune AV"
  if [ ! -f "$app_binary" ]; then
    echo "FAIL archive app binary is missing: $app_binary" >&2
    exit 1
  fi
  app_archs="$(lipo -archs "$app_binary")"
  if [ "$app_archs" != "arm64" ]; then
    echo "FAIL macOS archive must be Apple Silicon-only arm64, got: $app_archs" >&2
    exit 1
  fi

  echo "Archive bundle identifier check passed."
  echo "Archive architecture check passed: $app_archs."

  if [ -n "$cleanup_dir" ]; then
    rm -rf "$cleanup_dir"
  fi
fi

echo
echo "macOS release preflight passed."
