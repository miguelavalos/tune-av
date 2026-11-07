# App Store Review Notes

Use this public checklist before attaching a new iOS or macOS build to App Store
review. Keep private credentials, reviewer accounts, provisioning details, and
approval records outside this repository.

## Release Scope

- [The approved Pro sync scope](pro-sync-scope.md) covers only explicitly saved
  stations and explicitly saved songs for signed-in Pro accounts.
- Feedback remains user-visible only on the device where it was given. A
  deliberate Pro feedback action may upload once for server-side summaries and
  recommendations, but it is not downloaded, restored, or delivered through
  realtime sync. Guest and signed-in Free feedback remains fully local.
- Recents, discovery history, playback state, and device settings are local-only.
- Saved song sync is based on active saved-song records. Discovery history and
  feedback can differ across devices by design.
- iOS and macOS should be tested together with the same signed-in Pro account
  before submission.
- macOS builds universal (Apple Silicon and Intel) since `1.0.9`; the earlier
  Apple Silicon-only constraint came from the Convex Swift binary dependency,
  removed on 2026-11-01.
- macOS TestFlight/App Store auth uses the stable Account AV keychain service
  `com.avalsys.tuneav.account.v2` and the team-prefixed keychain access group
  `<team id>.com.avalsys.tuneav` set in `apps/macos/Config/Release.xcconfig`;
  repeated Keychain access prompts are not expected in a clean signed build.
- The old macOS Account AV keychain service `com.avalsys.tuneav.account` must
  not be reused. If a macOS TestFlight build prompts for login-keychain access
  to that service, discard the build and ship a new build with the `.v2`
  service.
- Missing account tokens or missing generated runtime config are handled as
  local availability states and should not surface as reviewer-visible raw
  diagnostics.

## Current App Store Status

- Latest App Store approved versions: iOS/iPadOS `1.0.7 (56)` and macOS
  `1.0.7 (64)`, approved in July 2026.
- Latest TestFlight builds: iOS/iPadOS `1.1.1 (64)` and macOS `1.1.1 (69)`
  from public commit `714bac4`, uploaded on 2026-11-07 and available to the
  internal testers only; not submitted to App Review. Every TestFlight build
  since `1.0.8` has had the same scope.
- [ios-current-state.md](ios-current-state.md) and the delivery checkpoints in
  [release-checklist.md](release-checklist.md) carry the public build list.
  Upload, processing, tester-group and review records live in the private
  release runbook.
- macOS has shipped on the App Store since `1.0.4`, so release notes for both
  platforms describe the changes of the version; first-release copy such as
  `Tune AV is now available on Mac.` no longer applies.
- macOS App Store screenshots are prepared locally in
  `docs/app-store/screenshots/macos/` (`01-home.png`, `02-search.png`,
  `03-music.png`, `04-library.png`, `05-profile.png`, `1440 x 900` PNGs). The
  folder is intentionally gitignored: they are release assets, not public
  source files.

## Suggested Review Notes

Tune AV uses Account AV sign-in and Tune AV Pro for cloud sync. With a signed-in
Pro account, explicitly saved radios and explicitly saved songs sync between iOS
and macOS. Recents, discovery history, playback state, device settings, station
feedback, and song feedback remain local to each device by design. A deliberate
Pro feedback action may be retained by the backend for summaries and
recommendations, but it is not restored on another device.

If a reviewer account is needed, provide it only in App Store Connect review
notes or private release operations, never in this public repository.

## Metadata And Legal Checks

- App Store privacy answers must cover the app's data practices across iOS and
  macOS, including third-party partners and any data linked to the account.
- Confirm the privacy policy and App Store privacy labels describe account-linked
  product interaction or preference data if saved radios, saved songs, or
  feedback are collected for sync, personalization, analytics, or support.
- Confirm the macOS archive contains `Contents/Resources/PrivacyInfo.xcprivacy`
  and that App Store Connect declares account-linked Product Interaction data
  used for App Functionality and Analytics before enabling macOS listening
  analytics in production.
- Confirm diagnostics and support copy do not describe expected logout,
  restore, or local config availability windows as production errors.
- Confirm support, privacy policy, terms, and account deletion links open from
  the app and from App Store Connect metadata.
- Confirm subscription copy and pricing match the active Tune AV Pro product in
  App Store Connect.
- Confirm macOS metadata matches the universal (Apple Silicon and Intel)
  release target; it no longer needs to exclude Intel Macs.

Apple references:

- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [App Review preparation](https://developer.apple.com/distribute/app-review/)
