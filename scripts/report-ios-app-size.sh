#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${TUNEAV_IOS_APP_PATH:-$ROOT_DIR/.derived-data/ios-ci/Build/Products/Debug-iphonesimulator/TuneAV.app}"
REPORT_PATH="${TUNEAV_IOS_SIZE_REPORT_PATH:-$ROOT_DIR/.derived-data/ios-ci/Reports/app-size.md}"
MAX_APP_SIZE_BYTES="${TUNEAV_IOS_MAX_APP_SIZE_BYTES:-157286400}"
MAX_EXECUTABLE_SIZE_BYTES="${TUNEAV_IOS_MAX_EXECUTABLE_SIZE_BYTES:-20971520}"
MAX_ASSETS_SIZE_BYTES="${TUNEAV_IOS_MAX_ASSETS_SIZE_BYTES:-31457280}"
MAX_FRAMEWORKS_SIZE_BYTES="${TUNEAV_IOS_MAX_FRAMEWORKS_SIZE_BYTES:-62914560}"
MAX_PLUGINS_SIZE_BYTES="${TUNEAV_IOS_MAX_PLUGINS_SIZE_BYTES:-20971520}"

rm -f "$REPORT_PATH"
mkdir -p "$(dirname "$REPORT_PATH")"

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

check_size_budget() {
  local label="$1"
  local path="$2"
  local max_bytes="$3"

  if [[ "$max_bytes" == "0" || ! -e "$path" ]]; then
    return 0
  fi

  local bytes
  bytes="$(bytes_for_path "$path")"
  if [[ "$bytes" -gt "$max_bytes" ]]; then
    echo "FAIL $label exceeds max size: $(human_bytes "$bytes") > $(human_bytes "$max_bytes")." >&2
    return 1
  fi
}

write_budget_row() {
  local label="$1"
  local path="$2"
  local max_bytes="$3"

  if [[ ! -e "$path" ]]; then
    printf '| %s | n/a | n/a | missing |\n' "$label"
    return
  fi

  local bytes status budget
  bytes="$(bytes_for_path "$path")"
  if [[ "$max_bytes" == "0" ]]; then
    budget="disabled"
    status="reported"
  elif [[ "$bytes" -gt "$max_bytes" ]]; then
    budget="$(human_bytes "$max_bytes")"
    status="fail"
  else
    budget="$(human_bytes "$max_bytes")"
    status="pass"
  fi

  printf '| %s | %s | %s | %s |\n' "$label" "$(human_bytes "$bytes")" "$budget" "$status"
}

app_bytes="$(bytes_for_path "$APP_PATH")"
executable_path="$APP_PATH/TuneAV"
assets_path="$APP_PATH/Assets.car"
frameworks_path="$APP_PATH/Frameworks"
plugins_path="$APP_PATH/PlugIns"

{
  echo "# iOS App Size Report"
  echo
  echo "| Metric | Size | Path |"
  echo "| --- | ---: | --- |"
  write_size_row "App bundle" "$APP_PATH"
  write_size_row "Executable" "$executable_path"
  write_size_row "Assets catalog" "$assets_path"
  write_size_row "Frameworks" "$frameworks_path"
  write_size_row "PlugIns" "$plugins_path"
  echo
  echo "## Size Budgets"
  echo
  echo "| Metric | Size | Budget | Status |"
  echo "| --- | ---: | ---: | --- |"
  write_budget_row "App bundle" "$APP_PATH" "$MAX_APP_SIZE_BYTES"
  write_budget_row "Executable" "$executable_path" "$MAX_EXECUTABLE_SIZE_BYTES"
  write_budget_row "Assets catalog" "$assets_path" "$MAX_ASSETS_SIZE_BYTES"
  write_budget_row "Frameworks" "$frameworks_path" "$MAX_FRAMEWORKS_SIZE_BYTES"
  write_budget_row "PlugIns" "$plugins_path" "$MAX_PLUGINS_SIZE_BYTES"
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

budget_failures=0
check_size_budget "iOS app bundle" "$APP_PATH" "$MAX_APP_SIZE_BYTES" || budget_failures=$((budget_failures + 1))
check_size_budget "iOS executable" "$executable_path" "$MAX_EXECUTABLE_SIZE_BYTES" || budget_failures=$((budget_failures + 1))
check_size_budget "iOS assets catalog" "$assets_path" "$MAX_ASSETS_SIZE_BYTES" || budget_failures=$((budget_failures + 1))
check_size_budget "iOS frameworks" "$frameworks_path" "$MAX_FRAMEWORKS_SIZE_BYTES" || budget_failures=$((budget_failures + 1))
check_size_budget "iOS plug-ins" "$plugins_path" "$MAX_PLUGINS_SIZE_BYTES" || budget_failures=$((budget_failures + 1))

if [[ "$budget_failures" -gt 0 ]]; then
  echo "Set the relevant TUNEAV_IOS_MAX_*_SIZE_BYTES variable to 0 to report without enforcing that limit." >&2
  exit 1
fi
