#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

workflow_dir=".github/workflows"

if [[ ! -d "$workflow_dir" ]]; then
  printf 'GitHub Actions workflow directory not found: %s\n' "$workflow_dir" >&2
  exit 1
fi

mutable_uses_pattern='uses:[[:space:]]+[^[:space:]#]+@(v[0-9]+([.][0-9]+)*|main|master|HEAD|latest)([[:space:]]|$)'

if matches="$(rg -n "$mutable_uses_pattern" "$workflow_dir" --glob '*.yml' --glob '*.yaml')" && [[ -n "$matches" ]]; then
  printf '%s\n' "$matches" >&2
  printf 'GitHub Actions must be pinned to full commit SHAs, not mutable tags or branches.\n' >&2
  exit 1
fi

short_sha_pattern='uses:[[:space:]]+[^[:space:]#]+@[0-9a-fA-F]{7,39}([[:space:]]|$)'

if matches="$(rg -n "$short_sha_pattern" "$workflow_dir" --glob '*.yml' --glob '*.yaml')" && [[ -n "$matches" ]]; then
  printf '%s\n' "$matches" >&2
  printf 'GitHub Actions must be pinned to 40-character commit SHAs.\n' >&2
  exit 1
fi

printf 'GitHub Actions pinning check passed.\n'
