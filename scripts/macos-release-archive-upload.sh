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
  scripts/macos-release-archive-upload.sh [--build <build>] [--version <version>]
    [--archive <path>] [--upload] [--skip-preflight]

Reproducible Tune AV macOS release workflow:
1. validates generated prod config and release gates;
2. creates a signed Apple Silicon-only Xcode archive;
3. verifies bundle id, team id, signing class, and arm64 architecture;
4. uploads to App Store Connect only when --upload is passed.

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

plist="$repo_root/apps/macos/Supporting/Info.plist"

plist_set() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
}

plist_get() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$plist"
}

if [ -n "$archive_path" ] && [ -d "$archive_path" ]; then
  use_existing_archive=1
  archive_path="$(cd "$(dirname "$archive_path")" && pwd)/$(basename "$archive_path")"
fi

if [ "$use_existing_archive" -eq 0 ]; then
  if [ -n "$build_number" ]; then
    run_step "Set macOS build number $build_number"
    plist_set "CFBundleVersion" "$build_number"
  fi

  if [ -n "$version_number" ]; then
    run_step "Set macOS marketing version $version_number"
    plist_set "CFBundleShortVersionString" "$version_number"
  fi

  build_number="$(plist_get "CFBundleVersion")"
  version_number="$(plist_get "CFBundleShortVersionString")"
else
  app_info="$archive_path/Products/Applications/Tune AV.app/Contents/Info.plist"
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
  archive_path="$repo_root/.derived-data/macos-release-archives/TuneAVMac-${version_number}-${build_number}-${timestamp}.xcarchive"
fi

mkdir -p "$(dirname "$archive_path")"

if [ "$skip_preflight" -eq 0 ] && [ "$use_existing_archive" -eq 0 ]; then
  run_step "Run macOS release preflight without archive"
  (cd "$repo_root" && bun run macos:release:preflight)
fi

if [ "$use_existing_archive" -eq 0 ]; then
  run_step "Archive signed Apple Silicon macOS release"
  xcodebuild archive \
    -project "$repo_root/apps/macos/TuneAVMac.xcodeproj" \
    -scheme TuneAVMac \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    -derivedDataPath "$repo_root/.derived-data/macos-release-derived-data" \
    -allowProvisioningUpdates \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO
else
  run_step "Use existing macOS archive"
  echo "$archive_path"
fi

run_step "Verify final macOS release archive"
"$repo_root/scripts/check-macos-archive-signing.sh" --archive "$archive_path"

if [ "$upload" -eq 1 ]; then
  run_step "Upload verified macOS archive to App Store Connect"
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$repo_root/.derived-data/macos-release-uploads/TuneAVMac-${version_number}-${build_number}" \
    -exportOptionsPlist "$repo_root/apps/macos/Config/ExportOptionsUpload.plist" \
    -allowProvisioningUpdates
else
  cat <<REPORT

Verified archive is ready.
  archive: $archive_path

To upload this exact archive, rerun:
  bun run macos:release:upload -- --archive "$archive_path" --upload --skip-preflight
REPORT
fi
