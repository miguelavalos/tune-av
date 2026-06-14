#!/usr/bin/env bash
set -euo pipefail

archive_path=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/repair-macos-archive-sentry-dsym.sh --archive <TuneAVMac.xcarchive>

Generates the dSYM for Xcode's Sentry.framework stub inside a Tune AV macOS
archive. Xcode can inject a generated binary into Sentry's codeless framework
during archive/export; App Store Connect then expects a matching dSYM UUID.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      archive_path="${2:-}"
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

if [ -z "$archive_path" ]; then
  echo "--archive is required." >&2
  usage >&2
  exit 2
fi

case "$archive_path" in
  *.xcarchive) ;;
  *)
    echo "--archive must point to a .xcarchive bundle: $archive_path" >&2
    exit 2
    ;;
esac

archive_path="$(cd "$(dirname "$archive_path")" && pwd)/$(basename "$archive_path")"
sentry_binary="$archive_path/Products/Applications/Tune AV.app/Contents/Frameworks/Sentry.framework/Versions/A/Sentry"
sentry_dsym="$archive_path/dSYMs/Sentry.framework.dSYM"

if [ ! -f "$sentry_binary" ]; then
  echo "Sentry framework binary not found in archive; nothing to repair: $sentry_binary"
  exit 0
fi

binary_uuid="$(dwarfdump --uuid "$sentry_binary" | awk '/UUID:/ {print $2; exit}')"
if [ -z "$binary_uuid" ]; then
  echo "Could not read Sentry framework UUID from $sentry_binary" >&2
  exit 1
fi

if [ -d "$sentry_dsym" ]; then
  dsym_uuid="$(dwarfdump --uuid "$sentry_dsym" | awk '/UUID:/ {print $2; exit}')"
  if [ "$dsym_uuid" = "$binary_uuid" ]; then
    echo "Sentry.framework.dSYM already matches archive UUID $binary_uuid."
    exit 0
  fi
  echo "Replacing mismatched Sentry.framework.dSYM UUID ${dsym_uuid:-<missing>} with $binary_uuid."
  rm -rf "$sentry_dsym"
fi

mkdir -p "$archive_path/dSYMs"
xcrun dsymutil "$sentry_binary" -o "$sentry_dsym" >/dev/null

dsym_uuid="$(dwarfdump --uuid "$sentry_dsym" | awk '/UUID:/ {print $2; exit}')"
if [ "$dsym_uuid" != "$binary_uuid" ]; then
  echo "Generated Sentry dSYM UUID $dsym_uuid does not match binary UUID $binary_uuid." >&2
  exit 1
fi

echo "Generated Sentry.framework.dSYM for archive UUID $binary_uuid."
