# Changelog

All notable public client changes to Tune AV will be documented in this file.

This project follows semantic versioning once public source releases begin.

## Unreleased

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
- Improve cross-device library sync merge behavior for favorites, recents,
  discoveries, and settings.
- Add macOS sign-in presentation, account deletion entry, access refresh, and
  library sync UI.
- Align macOS Profile, player artwork details, preferred genre, and multilingual
  UI with the iOS app.
- Move the macOS app source from `apps/macos/TuneAVMac` to `apps/macos`.

## Repository Bootstrap

- Prepare Tune AV as a standalone public repository.
- Add public repository documentation for setup, contribution, support, and
  security reporting.
- Keep local configuration, signing, account, and release values outside tracked
  files.
