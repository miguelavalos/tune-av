# ASAP: AV Foundation From Tune AV

Goal: use Tune AV as the reference app for the AV product family before the
first App Store release.

Tune AV is already close to release. Before submitting it, we should review the
whole app and extract only the pieces that make sense as shared foundation for
future apps such as Moments AV and Series AV. The result should be a cleaner Tune
AV v1 and a stronger `apps-av` foundation.

This phase is not about migrating other apps yet. Moments AV, Series AV, and any
new app will start after Tune AV v1 is accepted and stable.

Status on 2026-05-22: PRs 1-8 are complete for the Tune AV v1 scope, and PR 9
has passed local release-candidate verification. The remaining work is outside
the shared extraction phase: signed App Store Connect upload, TestFlight build
processing, real-device release smoke, subscription/App Privacy checks, review
notes, and final screenshots.

## Principles

- Tune AV remains the source of truth for the first AV app structure.
- Shared code must improve control, consistency, and speed across future apps.
- No migrations, no legacy compatibility layers, no duplicate old/new paths.
- Every extraction must be used immediately by Tune AV.
- Tune AV should get simpler after each shared extraction.
- `apps-av` should stay generic: platform-specific code belongs under platform
  folders such as `apple/`, leaving room for Android or web later.
- App-specific features stay in Tune AV unless they are clearly reusable as a
  branded AV app pattern.

## What Should Be Considered For Shared

High-value candidates:

- Brand foundation: colors, typography, spacing, radius, icon sizing, motion,
  haptics, surface styles, and common visual tokens.
- App structure: splash, onboarding shell, main shell, footer, header actions,
  settings entry, account entry, safe-area behavior, and navigation shape.
- Avi foundation: entry points, companion surfaces, context indicator, action
  panels, reaction/emotion UI, detail surface patterns, and shared interaction
  contracts.
- Account/settings presentation: reusable UI structure around Account AV,
  profile shell, settings rows, legal/support/delete-account entry points.
- Paywall/limits presentation: common surfaces, blocked-action prompts, restore
  entry, entitlement-state UI, without forcing Tune-specific business logic.
- Localization and text-fit helpers: common labels, layout constraints, compact
  device behavior, reusable validation patterns.
- QA/release utilities: shared checklist structure, smoke-test flows, screenshot
  expectations, build verification conventions.

Low-value or not-now candidates:

- Tune-specific radio, station, playback, discovery, music, or recommendation
  models.
- Business logic that is likely to differ per app.
- Abstractions created only because another app may need them later.
- Shared APIs that mention Tune AV concepts.
- Compatibility wrappers around code we can delete cleanly.

## PR 1: Full Tune AV Shared Audit

Purpose: inspect the complete Tune AV app and decide what is worth sharing.

Status: complete. The audit produced the extraction path used by the subsequent
shared Apple foundation PRs.

Review:

- Splash and launch transition.
- Onboarding and first-run experience.
- Main shell and navigation.
- Footer and Avi entry.
- Header/logo/settings/account surfaces.
- Profile/settings/account/legal flows.
- Avi surfaces and interaction patterns.
- Paywall and limits.
- Localization and text fit.
- Existing use of `apps-av`, `account-av`, and local Tune AV components.

Deliverable:

- A short extraction map with three buckets:
  - move to `apps-av` now
  - keep in Tune AV
  - revisit after Tune AV v1
- No code changes unless needed to unblock the audit.

## PR 2: Shared Brand Foundation

Purpose: make AV branding controllable from one Apple shared package.

Status: complete for Tune AV v1. Tune consumes shared brand tokens from
`apps-av/apple`.

Move to `apps-av/apple` if the audit confirms stable patterns:

- Semantic brand colors.
- Typography roles.
- Spacing and layout constants.
- Corner radius and surface styles.
- Common icon sizing.
- Existing shared haptics alignment.
- Motion/duration constants if already repeated.

Tune AV cleanup:

- Replace local duplicated constants with shared foundation.
- Remove old local equivalents.
- Keep Tune-specific colors/assets only where they truly define Tune AV.

Verification:

- iOS Simulator build.
- Visual smoke on splash, onboarding, Home, Library, Music, Avi, Profile.

## PR 3: Shared App Shell

Purpose: ensure future AV apps share the same structural feel.

Status: complete for Tune AV v1. Tune consumes shared shell/header/footer
structure while keeping app-specific tabs and behavior local.

Move to shared only if the API can stay app-neutral:

- App shell container.
- Footer/tab structure.
- Avi central entry.
- Header action layout.
- Settings/account/logo placement.
- Safe-area and keyboard behavior.
- Selected/pressed states.

Tune AV cleanup:

- Tune AV provides app-specific tabs, labels, icons, and destinations.
- Shared code owns the layout and interaction shape.
- Delete replaced local shell components.

Verification:

- Simulator smoke: Home, Search, Library, Music, Avi, Profile.
- Confirm navigation state and footer selection remain correct.

## PR 4: Shared Splash And Onboarding Foundation

Purpose: make every AV app start with the same branded quality.

Status: complete for Tune AV v1. Tune keeps app-specific copy/assets and uses
shared launch/onboarding structure where app-neutral.

Move to shared:

- Splash layout pattern.
- Launch transition pattern.
- Onboarding page container.
- Account/legal entry layout.
- Shared buttons/surfaces used by onboarding.

Tune AV cleanup:

- Tune AV keeps its own copy, imagery, app name, and app-specific onboarding
  content.
- Shared code owns structure, spacing, transitions, and reusable states.

Verification:

- Fresh install simulator run.
- Guest path.
- Sign-in entry path.
- Legal links.
- Compact iPhone text fit.

## PR 5: Shared Account, Settings, And Legal Surfaces

Purpose: keep account/settings flows consistent across all AV apps while reusing
Account AV where appropriate.

Status: complete for Tune AV v1. Shared settings/account containers, cards, and
buttons are consumed by Tune.

Move to shared:

- Profile/settings shell.
- Settings row styles.
- Account entry card structure.
- Legal/support/delete-account row patterns.
- Empty/error/loading presentation where generic.

Keep outside shared:

- Account AV implementation details.
- App-specific settings.
- Tune-specific user-facing copy.

Tune AV cleanup:

- Replace local duplicated settings/profile UI.
- Keep Tune-specific settings as configuration/content.

Verification:

- Guest profile.
- Signed-in profile if available.
- Sign out.
- Delete-account entry.
- Legal/support links.

## PR 6: Shared Avi Foundation

Purpose: make Avi a consistent AV family interface while allowing each app to
define what Avi actually does.

Status: complete for Tune AV v1. Shared Avi controls and surfaces cover the
generic UI; radio/music/discovery behavior remains local to Tune.

Move to shared:

- Avi entry surface.
- Companion card/surface layout.
- Context indicator.
- Action panel structure.
- Detail surface pattern.
- Reaction/emotion presentation.
- Shared haptic events already available in `AVHaptics`.

Keep in Tune AV:

- Radio/music/discovery-specific Avi behavior.
- Tune-specific prompts, copy, and recommendations.
- Feature-specific data models.

Tune AV cleanup:

- Tune AV passes app-specific context and actions into shared Avi UI.
- Delete local generic Avi surfaces once replaced.

Verification:

- Open Avi from footer.
- Open radio details.
- Open music/discovery details.
- Trigger reactions/actions.
- Navigate back and across tabs.

## PR 7: Shared Paywall And Limit Surfaces

Purpose: make monetization UI consistent without locking future apps into Tune
AV business rules.

Status: complete for Tune AV v1. Shared paywall and upgrade-prompt scaffolds
are used by Tune while products, entitlements, limits, and copy stay local.

Move to shared:

- Paywall surface layout.
- Feature/benefit row style.
- Blocked-action prompt layout.
- Restore purchase entry pattern.
- Loading/error/entitlement presentation.

Keep in Tune AV:

- Product IDs.
- Entitlement mapping.
- Tune-specific limits.
- Tune-specific paywall copy.

Verification:

- Free/guest blocked action.
- Paywall display.
- Restore entry.
- Purchase error/offline state where practical.

## PR 8: Tune AV Cleanup And Consistency Pass

Purpose: make Tune AV the clean reference implementation.

Status: complete for Tune AV v1. The final text-fit pass landed in
`apps-av/apple` and Tune builds against it.

Do:

- Remove dead local components replaced by shared code.
- Remove duplicated styles and constants.
- Confirm no Tune-specific names leaked into `apps-av`.
- Confirm `apps-av` APIs are small, stable, and app-neutral.
- Confirm Tune AV still reads as Tune AV, not as a generic demo app.

Verification:

- iOS Simulator build.
- Unit tests if present.
- Simulator smoke across all primary flows.
- Review repo status in both `tune-av` and `apps-av`.

## PR 9: Tune AV Release Candidate

Purpose: freeze the first Tune AV version for TestFlight and App Store.

Status: App Review resubmission active on 2026-05-28. `apps-av/apple` builds,
Tune unit/UI smoke checks pass, release preflight passes, strict archive privacy
evidence passes, App Store upload export options are checked in, and iOS `1.0`
build `13` has been uploaded after the subscription metadata/paywall update.
Remaining review work is tracked outside the public repository with private App
Store Connect, TestFlight, App Review, and provider evidence.

Run and verify `docs/release-checklist.md`.

Required:

- Clean repos.
- All intended commits pushed.
- iOS Simulator build passes.
- Physical-device smoke test passes.
- Physical-device haptics pass completed.
- App Store privacy/legal/support/delete-account material ready.
- Screenshots captured from a release-equivalent build.
- TestFlight build processed.
- No known v1 blockers remain.

Deliverable:

- Tune AV v1 release candidate ready for App Store submission.

## Definition Of Done

This phase is done when:

- Tune AV is ready to submit as the first AV app.
- `apps-av` contains only shared code that Tune AV actually uses.
- Tune AV no longer carries duplicated local versions of extracted foundation
  code.
- The shared Apple foundation is app-neutral and leaves room for Android or web
  platform folders later.
- Moments AV and Series AV can start after release using Tune AV plus `apps-av`
  as the reference, without copying unstable local code.
