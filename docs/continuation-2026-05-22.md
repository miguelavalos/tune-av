# Tune AV Client Continuation

Date: 2026-05-22

This document captures the public client handoff point after the Tune AV shared
foundation extraction. It intentionally excludes release status, signing,
service configuration, private operations, and approval evidence.

## Current State

- Tune AV remains the source of truth for the first native client.
- Shared Apple foundation used by Tune now covers app-neutral brand tokens,
  shell, launch/splash support, settings/account surfaces, Avi controls,
  paywall/limit surfaces, and localization text-fit hardening.
- Tune-specific radio, station, playback, discovery, music, recommendation,
  product, entitlement, limit, and copy logic remains in Tune AV.

## Verified On 2026-05-22

- shared Apple package build passed.
- Tune AV unit tests: 286 passed, 0 failed.
- Tune AV Home UI smoke: 1 passed, 0 failed.
- Tune AV Debug build/run launched successfully.

## Local Environment Note

During simulator launch, iOS can show Apple ID prompts for the simulator
account. Those prompts are external simulator state and do not indicate a Tune
AV crash. Use a clean simulator account state for visual QA.

## Recommended Next Step

Continue client work through [release-checklist.md](release-checklist.md):

- keep repository hygiene clean;
- run local iOS build/tests;
- smoke-test changed UI flows;
- keep shared Apple APIs app-neutral;
- keep private operations and distribution details outside public docs.
