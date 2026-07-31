#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
archive_path=""
build_number=""
version_number=""
upload=0
skip_preflight=0
use_existing_archive=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/ios-release-archive-upload.sh [--build <build>] [--version <version>]
    [--archive <path>] [--upload] [--skip-preflight]

Reproducible Tune AV iOS release workflow:
1. validates generated prod config and release gates;
2. creates a signed Xcode archive;
3. repairs the Sentry.framework dSYM inside the final archive;
4. verifies bundle id, team id, build, app dSYM, and Sentry dSYM;
5. uploads to App Store Connect only when --upload is passed.

Before unattended --upload from a new/reconfigured Mac, complete the private
apple-release-machine setup so the Distribution key can codesign without a
password prompt.

Without --upload, this is a dry run that leaves a verified .xcarchive ready for
manual distribution.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      archive_path="${2:-}"
      shift 2
      ;;
    --build)
      build_number="${2:-}"
      shift 2
      ;;
    --version)
      version_number="${2:-}"
      shift 2
      ;;
    --upload)
      upload=1
      shift
      ;;
    --skip-preflight)
      skip_preflight=1
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

run_step() {
  echo
  echo "==> $*"
}

plist_set() {
  local key="$1"
  local value="$2"
  local plist="$repo_root/apps/ios/TuneAV/App/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
}

plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$repo_root/apps/ios/TuneAV/App/Info.plist"
}

if [ -n "$archive_path" ] && [ -d "$archive_path" ]; then
  use_existing_archive=1
  archive_path="$(cd "$(dirname "$archive_path")" && pwd)/$(basename "$archive_path")"
fi

if [ "$use_existing_archive" -eq 0 ]; then
  if [ -n "$build_number" ]; then
    run_step "Set iOS build number $build_number"
    plist_set "CFBundleVersion" "$build_number"
  fi

  if [ -n "$version_number" ]; then
    run_step "Set iOS marketing version $version_number"
    plist_set "CFBundleShortVersionString" "$version_number"
  fi

  build_number="$(plist_get "CFBundleVersion")"
  version_number="$(plist_get "CFBundleShortVersionString")"
else
  app_info="$archive_path/Products/Applications/TuneAV.app/Info.plist"
  [ -f "$app_info" ] || { echo "Existing archive app Info.plist is missing: $app_info" >&2; exit 1; }
  if [ -z "$build_number" ]; then
    build_number="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app_info")"
  fi
  if [ -z "$version_number" ]; then
    version_number="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_info")"
  fi
fi

if [ -z "$archive_path" ]; then
  timestamp="$(date '+%Y-%m-%d-%H%M%S')"
  archive_path="$repo_root/.derived-data/release-archives/TuneAV-${version_number}-${build_number}-${timestamp}.xcarchive"
fi

mkdir -p "$(dirname "$archive_path")"

if [ "$skip_preflight" -eq 0 ] && [ "$use_existing_archive" -eq 0 ]; then
  run_step "Run iOS release preflight without archive"
  (cd "$repo_root" && vp run ios:release:preflight)
fi

if [ "$use_existing_archive" -eq 0 ]; then
  run_step "Archive signed iOS release"
  xcodebuild archive \
    -project "$repo_root/apps/ios/TuneAV.xcodeproj" \
    -scheme TuneAV \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$archive_path" \
    -derivedDataPath "$repo_root/.derived-data/release-derived-data" \
    -allowProvisioningUpdates
else
  run_step "Use existing iOS archive"
  echo "$archive_path"
fi

run_step "Repair Sentry.framework dSYM in final archive"
"$repo_root/scripts/repair-ios-archive-sentry-dsym.sh" --archive "$archive_path"

run_step "Verify final iOS release archive"
"$repo_root/scripts/check-ios-release-archive.sh" \
  --archive "$archive_path" \
  --expected-build "$build_number" \
  --expected-version "$version_number"

if [ "$upload" -eq 1 ]; then
  run_step "Upload verified archive to App Store Connect"
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$repo_root/.derived-data/release-uploads/TuneAV-${version_number}-${build_number}" \
    -exportOptionsPlist "$repo_root/apps/ios/Config/ExportOptionsUpload.plist" \
    -allowProvisioningUpdates
else
  cat <<REPORT

Verified archive is ready.
  archive: $archive_path

To upload this exact archive, rerun:
  vp run ios:release:upload -- --archive "$archive_path" --upload --skip-preflight
REPORT
fi
