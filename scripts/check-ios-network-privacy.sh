#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
client_file="$repo_root/apps/ios/TuneAV/App/AVAccountAPIClient.swift"
app_data_file="$repo_root/apps/ios/TuneAV/App/TuneAVAppDataService.swift"

failures=0

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    fail "missing required file: ${file#$repo_root/}"
  fi
}

require_file "$client_file"
require_file "$app_data_file"

if [ "$failures" -gt 0 ]; then
  exit 1
fi

network_log_lines="$(rg -n 'networkLogger\.(debug|info|error|fault|notice|warning)' "$client_file" || true)"
if [ -z "$network_log_lines" ]; then
  fail "AVAccountAPIClient must keep explicit networkLogger events for release diagnostics"
fi

if printf '%s\n' "$network_log_lines" | rg -qi 'token|bearer|authorization|header|body|payload|httpBody|url|absoluteString|query|path|localizedDescription|String\(reflecting'; then
  printf '%s\n' "$network_log_lines" >&2
  fail "networkLogger lines must not expose tokens, headers, bodies, URLs, queries, paths, or raw errors"
fi

if rg -n 'Logger\(|print\(|debugPrint\(|NSLog\(' "$app_data_file"; then
  fail "TuneAVAppDataService should not log account-backed analytics, feedback, or library payloads"
fi

network_event_block="$(sed -n '/struct NetworkEvent/,/struct RetryPolicy/p' "$client_file")"
if printf '%s\n' "$network_event_block" | rg -qi 'url|path|query|body|payload|token|authorization|header|stationName|title|artist'; then
  printf '%s\n' "$network_event_block" >&2
  fail "NetworkEvent must stay metadata-only and must not store request/user payload fields"
fi

operation_name_block="$(sed -n '/private static func operationName/,/^    }/p' "$client_file")"
if ! printf '%s\n' "$operation_name_block" | rg -Fq 'split(separator: "?"'; then
  fail "operationName must strip query strings before deriving metrics labels"
fi

if ! printf '%s\n' "$operation_name_block" | rg -Fq 'unknown.\(method.lowercased())'; then
  fail "unknown API routes must collapse to method-only operation names"
fi

if rg -n 'privacy: \.public.*(token|bearer|authorization|header|body|payload|httpBody|absoluteString|localizedDescription|String\(reflecting)' "$repo_root/apps/ios/TuneAV/App" "$repo_root/apps/ios/TuneAV/Features" "$repo_root/apps/ios/TuneAV/Core"; then
  fail "public OSLog interpolation must not include sensitive network/auth payload fields"
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "iOS network privacy check passed."
