# ASAP: Tune AV v1

Goal: finish Tune AV as the first complete, stable, App Store-ready AV app.

This document is intentionally focused on Tune AV. Do not use this phase to extract
large shared UI packages or migrate Moments AV / Series AV. Tune AV is the reference
app; shared packages should only grow when they directly help Tune AV ship cleanly.

## Release Principle

- Tune AV v1 must feel coherent across splash, onboarding, shell, footer, Avi,
  playback, library, profile, settings, paywall, and account flows.
- Prefer fixing Tune AV in place over abstracting too early.
- No legacy wrappers or migration layers.
- Every PR should leave the app cleaner, buildable, and tested.
- Anything extracted to `apps-av` must be immediately used by Tune AV and must
  remove local duplication.

## PR 1: Visual Structure And Branding Audit

Purpose: make Tune AV internally consistent before App Store work.

Check:

- Splash visual quality and launch transition.
- Onboarding visual quality and Account AV entry points.
- Header: settings, logo, account.
- Footer: tab shape, selected state, Avi button, safe area behavior.
- Avi surfaces: companion card, full player, action panel, detail screens.
- Profile/settings cards and empty states.
- Typography, corner radius, spacing, shadows, icon weight, and accent use.
- German/English/Catalan/Spanish text fit on compact iPhones.

Deliverable:

- Small UI fixes only where inconsistency is visible.
- Build iOS Simulator.
- Simulator smoke test Home, Search, Library, Music, Avi, Profile.

## PR 2: First-Run, Onboarding, Account

Purpose: ensure the first user experience is App Store-ready.

Check:

- Fresh install path.
- Guest mode path.
- Sign in entry points.
- Account unavailable state.
- Sign out.
- Account deletion flow.
- Legal links from onboarding/profile.
- Error states for auth failures.

Deliverable:

- Fix broken, unclear, or visually inconsistent onboarding/account behavior.
- Build and targeted smoke tests.

## PR 3: Core Product Flows

Purpose: validate Tune AV's real value loop.

Check:

- Home daily desk.
- Play station.
- Stop/close signal.
- Full player.
- Search station.
- Favorite/unfavorite.
- Station feedback: like, not for me, dislike, clear.
- Recent/favorite/tuned library modes.
- Music/discoveries save/unsave and feedback.
- Last played resume.
- Cellular playback warning if enabled.

Deliverable:

- Fix blockers and obvious UX breaks.
- Keep feature changes minimal unless they are required for v1 quality.
- Build and simulator smoke test.

## PR 4: Avi v1 Quality Pass

Purpose: make Avi feel like a coherent product pillar, not a decorative layer.

Check:

- Avi entry from footer.
- Avi active context indicator.
- Avi full player state.
- Avi radio details.
- Avi music/discovery details.
- Avi action panels.
- Avi emotions/reactions.
- Haptics on physical device later.
- No repeated or noisy reactions.

Deliverable:

- Fix interaction bugs, layout issues, and noisy transitions.
- Simulator smoke test; physical-device haptics pass before release candidate.

## PR 5: Paywall, Limits, Purchases

Purpose: make monetization/restrictions review-safe and understandable.

Check:

- Pro paywall copy.
- Guest/free/pro limits.
- Upgrade prompts from blocked actions.
- Restore purchases.
- RevenueCat entitlement state handling.
- Offline or failed purchase states.

Deliverable:

- Fix review-blocking or confusing behavior.
- Build and targeted tests where available.

## PR 6: App Store Technical Readiness

Purpose: prepare the exact build path for Apple submission.

Run and verify the existing release checklist in `docs/release-checklist.md`.

Check:

- Production config generation.
- Bundle identifier.
- Version/build number.
- App icon and launch assets.
- Privacy manifest evidence.
- Third-party SDK inventory.
- Legal/support/delete-account URLs.
- ATS review notes for live radio HTTP streams.
- Archive preflight.
- App size budget.

Deliverable:

- Release checklist passes or has documented, accepted exceptions.
- No private config or signing artifacts committed.

## PR 7: Localization And Text Fit

Purpose: avoid App Store screenshots and real devices showing broken text.

Check:

- English.
- Spanish.
- Catalan.
- German.
- Compact iPhone.
- Large Dynamic Type where practical.
- Buttons, pills, cards, nav labels, paywall, onboarding, profile.

Deliverable:

- Fix truncation, overflow, awkward copy, and missing localized strings.
- Build and simulator screenshots for key screens.

## PR 8: Release Candidate

Purpose: freeze Tune AV v1 for TestFlight/App Store.

Required:

- Clean repo.
- All intended commits pushed.
- iOS Simulator build passes.
- Unit tests pass.
- Release preflight passes.
- Archive preflight passes.
- Physical-device smoke completed.
- Haptics physical-device pass completed.
- App Store screenshots captured from release-equivalent build.
- TestFlight build processed.

Deliverable:

- Release candidate tag or release branch, depending on final workflow.

## Shared Package Rule During v1

Allowed:

- Small, stable utilities already proven in Tune AV.
- Code that Tune AV consumes immediately.
- Code that removes local duplication without changing product behavior.

Not allowed during v1:

- Large shell/branding extraction just to prepare Moments AV or Series AV.
- Generic abstractions that delay Tune AV release.
- Compatibility wrappers.
- Shared APIs that still mention Tune-specific models.

Current shared package status:

- `apps-av/apple/AVHaptics` is accepted and already used by Tune AV.
- Further shared work should wait unless it directly improves Tune AV v1.

## Definition Of Done

Tune AV v1 is done when:

- The app feels visually coherent.
- First-run, guest, account, playback, library, Avi, profile, paywall, and legal
  flows work.
- Build, tests, simulator smoke, physical-device smoke, and release preflight pass.
- App Store submission material is ready.
- No known v1 blockers remain.

