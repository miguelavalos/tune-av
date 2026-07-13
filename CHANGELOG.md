# Changelog

All notable public client changes to Tune AV will be documented in this file.

This project follows semantic versioning once public source releases begin.

## Unreleased

- Document the 2026-07-13 Pro sync decision: only explicitly saved stations and
  songs synchronize; feedback remains device-local and any deliberate Pro
  backend capture is upload-only, not cross-device restore.
- Mark TestFlight builds `52` and `61` as migration-pending under the narrowed
  contract; they remain historical saved-item sync evidence only.
- Remove feedback bootstrap, restore, and Convex-triggered reads from iOS and
  macOS while keeping the compatibility endpoint for older installed builds.
- Limit deliberate feedback uploads to Pro, with no Guest or signed-in Free
  backend request, and remove feedback outbox/Queue/Convex fanout.
- Update every Apple locale so Cloud Sync advertises only saved radios and
  saved songs; local feedback is no longer described as synchronized.

## 1.0.3 - 2026-06-28

- Add iPad-compatible iOS client support.
- Include minor iOS client bug fixes.

## 1.0.2 - 2026-06-25

- Reduce Pro cloud sync activity on iOS and macOS so Tune AV no longer keeps a
  continuous background polling loop while the app is open.
- Limit automatic Pro library refresh to the first app open or sign-in/access
  availability in the current app session; later refreshes can be triggered
  manually.
- Keep the existing local-first library merge behavior for saved stations,
  saved songs, feedback, and tombstones.

## 1.0.1 - 2026-06-14

- Complete the Tune AV shared-client foundation pass, consuming app-neutral
  Apple UI components from the shared Swift package.
- Verify the iOS client on 2026-05-22 with unit tests, Home UI smoke, config
  hygiene, and local app-size checks.
- Redesign the iOS full player around fixed-height Avi feedback, larger artwork,
  stable text truncation, and controls that do not shift between stations.
- Keep the full player in portrait orientation and hide the mini-player while
  the full player is visible.
- Preserve the active playback queue when resuming the last-played station from
  Home so Favorites/Recents lists keep next/previous behavior.
- Fix duplicate recent-station ranking so repeated recent entries cannot crash
  the library flow.
- Redesign the Tune AV Pro paywall so the primary purchase or sign-in action is
  visible before the benefit grid, with localized compact copy.
- Make Avi's visible emotion state adapt to the active screen, player state,
  radio metadata, discovered songs, feedback, saved tracks, and loading/error
  states.
- Refresh the redesigned iOS app shell tests for Avi, search, profile account
  mode, warning-based account deletion, queue playback, limits, and discovery
  flows.
- Share station feedback models across iOS and macOS so Apple targets compile
  against the same support layer.
- Improve cross-device library sync merge behavior for saved stations, saved
  songs, station feedback, and song feedback.
- Fix iOS startup retention so Pro feedback is not pruned by guest limits before
  account access state resolves.
- Suppress expected Account API missing-token and missing-base-URL diagnostics
  on iOS and macOS while keeping request failures and unexpected errors
  reportable.
- Add macOS sign-in presentation, account deletion entry, access refresh, and
  library sync UI.
- Align macOS Profile, player artwork details, preferred genre, and multilingual
  UI with the iOS app.
- Move the macOS app source from `apps/macos/TuneAVMac` to `apps/macos`.
- Keep signing team identifiers in generated local configuration rather than
  tracked Xcode project files.
- Add reproducible signed archive and upload workflows for iOS and macOS App
  Store Connect release builds.

## Repository Bootstrap

- Prepare Tune AV as a standalone public repository.
- Add public repository documentation for setup, contribution, support, and
  security reporting.
- Keep local configuration, signing, account, and release values outside tracked
  files.
