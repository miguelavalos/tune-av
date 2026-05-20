#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS="${TUNEAV_IOS_LAUNCH_PROFILE_RUNS:-3}"
REPORT_PATH="${TUNEAV_IOS_LAUNCH_PROFILE_REPORT_PATH:-$ROOT_DIR/.derived-data/ios-launch-performance-profile/report.md}"
LOG_DIR="${TUNEAV_IOS_LAUNCH_PROFILE_LOG_DIR:-$(dirname "$REPORT_PATH")/logs}"

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || [ "$RUNS" -lt 1 ]; then
  echo "TUNEAV_IOS_LAUNCH_PROFILE_RUNS must be a positive integer." >&2
  exit 1
fi

mkdir -p "$(dirname "$REPORT_PATH")" "$LOG_DIR"

measurements=()

for run in $(seq 1 "$RUNS"); do
  log_path="$LOG_DIR/run-$run.log"
  echo "==> Launch performance profile run $run/$RUNS"

  if ! "$ROOT_DIR/scripts/smoke-ios-launch-performance.sh" 2>&1 | tee "$log_path"; then
    echo "Launch performance run $run failed. See $log_path" >&2
    exit 1
  fi

  measurement="$(sed -nE 's/.*Tune AV launch ready: ([0-9]+)ms budget=.*/\1/p' "$log_path" | tail -1)"
  if [ -z "$measurement" ]; then
    echo "Could not parse launch ready measurement from $log_path" >&2
    exit 1
  fi

  measurements+=("$measurement")
done

node - "$REPORT_PATH" "$RUNS" "${measurements[@]}" <<'NODE'
const fs = require("node:fs");

const reportPath = process.argv[2];
const runs = Number(process.argv[3]);
const values = process.argv.slice(4).map(Number);
const sorted = [...values].sort((a, b) => a - b);
const median =
  sorted.length % 2 === 1
    ? sorted[(sorted.length - 1) / 2]
    : Math.round((sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2);
const average = Math.round(values.reduce((sum, value) => sum + value, 0) / values.length);
const min = sorted[0];
const max = sorted[sorted.length - 1];
const now = new Date().toISOString();

const lines = [
  "# iOS Launch Performance Profile",
  "",
  `Generated: ${now}`,
  `Runs: ${runs}`,
  "",
  "## Summary",
  "",
  `- Min: ${min} ms`,
  `- Median: ${median} ms`,
  `- Average: ${average} ms`,
  `- Max: ${max} ms`,
  "",
  "## Measurements",
  "",
  "| Run | Launch ready |",
  "| --- | ---: |",
  ...values.map((value, index) => `| ${index + 1} | ${value} ms |`),
  "",
  "## Notes",
  "",
  "- This profile measures time from UI test launch to the home tab bar being ready.",
  "- Run on the same simulator/runtime and avoid other heavy local work when comparing commits.",
  "- Use Instruments or ETTrace for stack-level attribution when this metric regresses.",
  "",
];

fs.writeFileSync(reportPath, `${lines.join("\n")}\n`);
console.log(`Launch performance profile written to ${reportPath}`);
NODE
