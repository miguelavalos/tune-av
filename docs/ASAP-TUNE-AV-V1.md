# Tune AV Shared Client Foundation

Goal: keep Tune AV as the reference SwiftUI client for shared Apple UI patterns
without exposing private release or operations material.

This phase is about frontend structure only. Release work, service
configuration, private service operations, and approval records belong outside
this public repository.

## Principles

- Tune AV remains the source of truth for the first native client structure.
- Shared code must improve control, consistency, and speed across future
  clients.
- Every extraction must be used immediately by Tune AV.
- Tune AV should get simpler after each shared extraction.
- Shared Apple code should stay app-neutral.
- App-specific radio, playback, discovery, music, and copy decisions stay in
  Tune AV.

## Shared Candidates

High-value candidates:

- Brand foundation: colors, typography, spacing, radius, icon sizing, motion,
  haptics, surface styles, and common visual tokens.
- App structure: splash, onboarding shell, main shell, footer, header actions,
  settings entry, account entry, safe-area behavior, and navigation shape.
- Avi foundation: entry points, companion surfaces, context indicator, action
  panels, reaction/emotion UI, detail surface patterns, and shared interaction
  contracts.
- Settings presentation: reusable UI structure around profile/settings rows,
  legal/support entries, and local data controls.
- Paywall/limits presentation: common surfaces, blocked-action prompts, restore
  entry, and loading/error presentation without app-specific business logic.
- Localization and text-fit helpers: common labels, layout constraints, compact
  device behavior, and reusable validation patterns.
- Client QA utilities: local build checks, UI smoke flows, screenshot
  expectations, and frontend verification conventions.

Low-value or not-now candidates:

- Tune-specific radio, station, playback, discovery, music, or recommendation
  models.
- Business logic likely to differ per app.
- Abstractions created only because another app may need them later.
- Shared APIs that mention Tune AV concepts.
- Compatibility wrappers around code we can delete cleanly.

## Completed Client Work

The Tune AV iOS client now uses shared Apple UI foundations for:

- brand tokens;
- shell/header/footer structure;
- launch and onboarding structure;
- settings/account presentation containers;
- Avi controls and surfaces;
- paywall and limit scaffolds;
- localization and text-fit hardening.

Tune-specific radio, playback, discovery, music, recommendation, product,
entitlement, limit, and copy logic remains in Tune AV.

## Public Verification

Use [release-checklist.md](release-checklist.md) for public client checks.

Minimum checks before public source changes:

- repository hygiene passes;
- iOS simulator build passes;
- iOS unit tests pass;
- targeted UI smoke passes for changed flows;
- shared Apple changes remain app-neutral;
- no private config, approval, service, signing, or operations material appears
  in public docs.

## Definition Of Done

This phase is done when:

- Tune AV remains a clear, working native client;
- shared Apple code contains only generic UI foundation used by Tune AV;
- Tune AV no longer carries duplicated local versions of extracted foundation
  code;
- future clients can reuse the shared Apple UI foundation without copying
  Tune-specific behavior.
