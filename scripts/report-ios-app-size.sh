#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${TUNEAV_IOS_APP_PATH:-$ROOT_DIR/.derived-data/ios-ci/Build/Products/Debug-iphonesimulator/TuneAV.app}"
REPORT_PATH="${TUNEAV_IOS_SIZE_REPORT_PATH:-$ROOT_DIR/.derived-data/ios-ci/Reports/app-size.md}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "FAIL $APP_PATH is missing. Run bun run ios:ci before generating the size report." >&2
  exit 1
fi

bytes_for_path() {
  /usr/bin/du -sk "$1" | awk '{ print $1 * 1024 }'
}

human_bytes() {
  awk -v bytes="$1" 'BEGIN {
    split("B KiB MiB GiB", units, " ");
    value = bytes;
    unit = 1;
    while (value >= 1024 && unit < 4) {
      value /= 1024;
      unit++;
    }
    printf "%.2f %s", value, units[unit];
  }'
}

write_size_row() {
  local label="$1"
  local path="$2"

  if [[ -e "$path" ]]; then
    local bytes
    bytes="$(bytes_for_path "$path")"
    printf '| %s | %s | `%s` |\n' "$label" "$(human_bytes "$bytes")" "${path#$ROOT_DIR/}"
  fi
}

mkdir -p "$(dirname "$REPORT_PATH")"

app_bytes="$(bytes_for_path "$APP_PATH")"
executable_path="$APP_PATH/TuneAV"

{
  echo "# iOS App Size Report"
  echo
  echo "| Metric | Size | Path |"
  echo "| --- | ---: | --- |"
  write_size_row "App bundle" "$APP_PATH"
  write_size_row "Executable" "$executable_path"
  write_size_row "Assets catalog" "$APP_PATH/Assets.car"
  write_size_row "Frameworks" "$APP_PATH/Frameworks"
  write_size_row "PlugIns" "$APP_PATH/PlugIns"
  echo
  echo "## Largest Bundle Files"
  echo
  echo "| Size | Path |"
  echo "| ---: | --- |"
  find "$APP_PATH" -type f -print0 |
    xargs -0 du -sk |
    sort -nr |
    head -20 |
    awk -v root="$ROOT_DIR/" '{
      size = $1 * 1024;
      path = $0;
      sub(/^[0-9]+[[:space:]]+/, "", path);
      sub(root, "", path);
      value = size;
      unit = "B";
      if (value >= 1024) { value /= 1024; unit = "KiB"; }
      if (value >= 1024) { value /= 1024; unit = "MiB"; }
      if (value >= 1024) { value /= 1024; unit = "GiB"; }
      printf "| %.2f %s | `%s` |\n", value, unit, path;
    }'
  echo
  echo "_Generated from \`${APP_PATH#$ROOT_DIR/}\`._"
} > "$REPORT_PATH"

echo "iOS app bundle size: $(human_bytes "$app_bytes")"
echo "iOS app size report written to $REPORT_PATH"
