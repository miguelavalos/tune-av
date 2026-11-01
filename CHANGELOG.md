# Changelog

All notable public client changes to Tune AV will be documented in this file.

This project follows semantic versioning once public source releases begin.

## Unreleased

## 1.0.9 - 2026-11-01

- Let Avi speak in first person on iOS and macOS: the Avi signals, moods, related
  radios, recommendation fallback and the Home brief now read as a companion
  talking to the listener in all five locales, and the Home brief notices a
  recent radio the listener has come back to three or more times this week.
- Add "Surprise me" to Home on iOS and macOS: one tap plays a radio Avi can
  justify from device-local signals (a rested or never-played favorite, a liked
  radio usual for this hour of day, a popular radio with a familiar tag, or a
  popular radio not played yet), never the current radio or one with negative
  feedback, through the normal play path with Avi's one-line reason on Home.
- Remove the Convex realtime layer from iOS and macOS: no `ConvexMobile`
  dependency, no `TUNEAV_CONVEX_URL`, and no realtime-session request. Pro
  cloud sync now pulls on app open, on foreground activation (throttled to once
  per minute), after sign-in, and on manual `Sync now`; repeated pulls send
  `If-None-Match` and treat `304 Not Modified` as unchanged.
- Build the macOS app for Apple Silicon and Intel again; the arm64-only
  constraint came from the removed Convex binary.
- Update RevenueCat to 5.100.0 so the iOS target compiles with Xcode 27.1.
- Meter Avi lookups (lyrics, YouTube, Spotify, Apple Music, web) for every
  tier instead of hiding them behind Pro: Guest 5 and Free 15 per day, Pro
  unlimited; the upgrade prompt appears only when the budget is exhausted.
- Raise Guest favorites to 10 and Free favorites to 30, mirroring the backend.
- Show the Pro paywall and the monthly StoreKit price without an account on
  iOS and macOS: RevenueCat is configured anonymously at launch and logs in
  when an Apps AV account appears; a guest who taps Subscribe signs in first
  and the purchase continues automatically. Entitlement still resolves
  through Apps AV.
- Open the paywall from every limit prompt, including for guests (sign-in
  stays available as a secondary action), and show the monthly free-trial
  intro offer text and plan-aware terms when App Store Connect defines one.
- Rewrite the paywall copy in all five locales around concrete value:
  unlimited Avi lookups, up to 1000 saved radios and songs, cloud sync between
  iPhone, iPad and Mac, price first.
- Add a one-time contextual upgrade moment after the 10th song discovered in a
  session or on the 3rd distinct listening day for Guest and Free listeners.
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
- Deliver replacement TestFlight candidates iOS/iPadOS `1.0.7 (53)` and macOS
  `1.0.7 (62)` from source commit `515bd93`; both uploads completed processing,
  became available to the internal TestFlight group, and remain outside App
  Review while focused physical verification completes.
- Verify on macOS TestFlight build `62` that one deliberate Pro feedback save
  produces one successful backend write and no feedback read, summary, retry,
  realtime request, or projection fanout during the bounded quiet window.
- Fix the shared iOS/macOS feedback-clear payload so station and song clears
  encode the backend-required `"feedback": null` instead of omitting the key;
  add exact-payload regressions and pass all 363 iOS and 63 macOS unit tests.
- Keep TestFlight builds `53` and `62` outside App Review because they predate
  this client repair; the temporary build-62 test reaction was removed with one
  exact production cleanup and no feedback-outbox change.
- Deliver repaired TestFlight candidates iOS/iPadOS `1.0.7 (54)` and macOS
  `1.0.7 (63)` from source commit `efc9515`; App Store Connect accepted both
  exact archives for processing, but processing completion and internal-group
  availability still require confirmation before installation or focused QA.

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
