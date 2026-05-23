# Changelog

All notable public changes to Tune AV will be documented in this file.

This project follows semantic versioning once public releases begin.

## Unreleased

- Submit Tune AV iOS `1.0` build `8` to Apple App Review on 2026-05-23.
- Prepare the iOS App Store upload path with checked-in export options and
  documented signed archive/export commands.
- Complete the Tune AV shared-foundation extraction pass for the first release
  candidate, consuming app-neutral Apple components from `apps-av/apple`.
- Verify the iOS release candidate on 2026-05-22 with unit tests, Home UI smoke,
  release config hygiene, archive privacy evidence, and app-size gate.
- Track post-submission work for the next release after the iOS 1.0 App Review submission.
- Redesign the iOS full player around fixed-height Avi feedback, larger artwork, stable text truncation, and controls that do not shift between stations.
- Keep the full player in portrait orientation and hide the mini-player while the full player is visible.
- Preserve the active playback queue when resuming the last-played station from Home so Favorites/Recents lists keep next/previous behavior.
- Fix duplicate recent-station ranking so repeated recent entries cannot crash the library flow.
- Redesign the Tune AV Pro paywall so the primary purchase or sign-in action is visible before the benefit grid, with localized compact copy.
- Add a temporary backend health gate for station discovery so repeated AVALSYS outages back off locally and fall back without hammering the backend.
- Make Avi's visible emotion state adapt to the active screen, player state, radio metadata, discovered songs, feedback, saved tracks, and loading/error states.
- Refresh the redesigned iOS app shell tests for Avi, search, profile account mode, warning-based account deletion, queue playback, limits, and discovery flows.
- Align shared Apple account deletion models so conservative linked-app, Pro, and subscription concerns appear as warnings unless the backend reports a hard blocker.
- Share station feedback models across iOS and macOS so Apple targets compile against the same support layer.
- Improve cross-device library sync merge behavior for favorites, recents, discoveries, and settings.
- Add macOS Account AV sign-in, account deletion, Pro/cloud access refresh, and backend library sync.
- Align macOS Profile, player artwork details, preferred genre, and multilingual UI with the iOS app.
- Move the macOS app source from `apps/macos/TuneAVMac` to `apps/macos`.

## 1.0 (iOS App Review submitted 2026-05-23)

- Submitted Tune AV iOS `1.0` build `8` to Apple App Review.
- Shipped the first App Store review candidate for iOS with radio playback, search, library, music discoveries, Account AV sign-in, local mode, and account safety flows.

## Repository Bootstrap

- Prepare Tune AV as a standalone public repository.
- Add public repository documentation for setup, contribution, support, and security reporting.
- Keep local configuration, signing, account, and release values outside tracked files.
