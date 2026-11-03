# Changelog

All notable public client changes to Tune AV will be documented in this file.

This project follows semantic versioning once public source releases begin.

## Unreleased

- Live Activity desactivada: la pantalla de bloqueo usa solo el reproductor del
  sistema, sin duplicado.
- Surprise me on Home no longer says a saved radio was "never played" when it
  was played before 1.1.0, more than two weeks ago or on another device: Avi
  now only says the radio is saved. Saved radios and recents count as played
  even with a different id or no logged date, so they are no longer offered as
  "New for you" either (iOS and macOS).

## 1.1.0 - 2026-11-03

iOS/iPadOS `1.1.0 (62)` and macOS `1.1.0 (67)`. Siri, Control Center, widgets,
the Live Activity and AirPlay are iPhone and iPad only; on Mac this release
changes only the paywall texts, the Terms and Privacy links and cached artwork.

iOS build `62` replaces `61`, which App Store Connect rejected with ITMS-90626
because App Intents string keys contained "siri": they are renamed from
`siri.*` to `appShortcut.*`, with the same texts.

- Siri, Shortcuts and the Action button on iPhone: "Play my radio on Tune AV"
  starts your last or favorite radio, "Pause Tune AV" pauses it, and "Play
  <radio> on Tune AV" starts one of your favorite or recent radios by name, in
  English, Spanish, Catalan, French and German. A "My radio" play/pause control
  is available in Control Center, on the Lock Screen and on the Action button
  (iOS 18). With the mobile data warning on, starting a radio opens the app so
  you can confirm; pausing always works in place.
- iPhone home-screen widgets: "My radio" (small) starts or pauses your last
  or favorite radio with one tap without opening the app, and "Radio and
  favorites" (medium) shows the current or last radio and song with play/pause
  plus up to four favorite radios as one-tap buttons. Lock Screen widgets play
  "My radio" too. Tapping elsewhere opens the player. The app shares a small
  snapshot with the widgets through the App Group.
- Live Activity on the iPhone lock screen and Dynamic Island while a radio
  plays: station, current song and artist, artwork (or the AV mark), a heart
  that saves the song (or the radio when there is no song) like the full
  player, and play/pause. It lives in the new `TuneAVWidgets` extension, which
  shares artwork with the app through the `group.<bundle id>` App Group.
- Add an AirPlay button to the iOS full player card, next to the station name,
  to send the radio to AirPlay speakers, Apple TV or Bluetooth.
- The Pro paywall on iPhone, iPad and Mac shows every text in full: titles,
  offer details, benefits, buttons and the Terms, Privacy, Restore and Redeem
  links wrap or stack instead of being cut off with "…" or shrunk. Prices,
  the monthly plan and purchases are unchanged.
- On Mac, the Terms and Privacy links in Settings and on the Pro paywall come
  from the same shared defaults as iOS, `https://tune-av.avalsys.com/terms`
  and `https://tune-av.avalsys.com/privacy`, unless private config sets other
  https URLs. The Mac already used these addresses, so the links look and
  open as before.
- On Mac, radio and song artwork that is already loaded shows at once when a
  view appears again, instead of flashing the placeholder first.
- Make the iOS launch-time check in CI steadier: it launches the app once
  without timing it, then times two more launches and keeps the faster one
  against the same budget. If the test loses its connection to the app on that
  first launch while the app is still on screen, it relaunches, up to three
  times. It fails if the app stops before or just after it reaches Home, and
  logs every measured time.

## 1.0.9 - 2026-11-01

- The Pro paywall on iPhone and iPad always shows the Terms and Privacy links,
  and the sign-in consent links no longer open missing pages: iOS and macOS use
  the public default URLs `https://tune-av.avalsys.com/terms` and
  `https://tune-av.avalsys.com/privacy` unless private config sets other https
  URLs.
- Three tabs on iPhone and iPad: Home, Explore (search with mood and genre
  chips) and Library, which joins Radios and Songs behind one segmented
  control. Avi stays the floating button and Profile stays in the header;
  routes and `TUNEAV_OPEN_TAB` values that opened Radios or Music now land on
  the matching Library segment.
- No more sentences cut off with "…" on iOS: shorter first-person Avi lines on
  Home and in the full player in all five languages, a short status pill on the
  Home card, and Avi texts and station names that wrap instead of truncating.
- Simplify Home on iOS: drop the "Daily Tuning Desk" title and the explanatory
  subtitles under every section, and remove the like, neutral and dislike
  buttons from the main Home card. Feedback stays in the player.
- Merge Avi picks and "around you" into a single "For You" row on iOS Home,
  shown before moods and genres.
- Redesign the iOS full player card: the current artwork blurred behind the
  card, a larger artwork, the song title in large white text and an animated AV
  live signal next to the station name that stops with Reduce Motion or Low
  Power Mode.
- Replace the song question, the three feedback buttons and the save / don't
  save row in the iOS full player with a single heart that saves the song (or
  the radio when the stream sends no title). A long press on the heart keeps
  like, not for me and dislike.
- Fix the main Home card on iOS in dark mode: the radio illustration now blends
  into the card as a soft line drawing instead of a grey block, and the header
  pills, badges and sparkle button are readable on the dark card. Light mode is
  unchanged.
- Open and close the iOS full player smoothly: the card grows from the mini
  player and the artwork moves into place with a short spring, and closing
  reverses it. With Reduce Motion on, the two simply crossfade.
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
