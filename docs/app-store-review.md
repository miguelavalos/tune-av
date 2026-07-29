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
- macOS is currently Apple Silicon-only while the Convex Swift binary dependency
  does not include an Intel macOS slice.
- macOS TestFlight/App Store auth uses the stable Account AV keychain service
  `com.avalsys.tuneav.account.v2` and keychain access group
  `935PM55U6R.com.avalsys.tuneav`; repeated Keychain access prompts are not
  expected in a clean signed build.
- The old macOS Account AV keychain service `com.avalsys.tuneav.account` must
  not be reused. If a macOS TestFlight build prompts for login-keychain access
  to that service, discard the build and ship a new build with the `.v2`
  service.
- Missing account tokens or missing generated runtime config are handled as
  local availability states and should not surface as reviewer-visible raw
  diagnostics.

## Suggested Public Release Copy

## Current App Store Status

- Approval checkpoint, 2026-07-29: the owner confirmed approval of
  iOS/iPadOS `1.0.7 (56)` and macOS `1.0.7 (64)`. A signed-in App Store Connect
  read listed both `1.0.7` platform versions as `Ready for Distribution`. No
  agent performed a post-approval manual-release action. Verify both exact
  builds after installation from App Store before closing the replacement
  release or retiring compatibility for older clients.

- Replacement delivery, 2026-07-13: iOS/iPadOS `1.0.7 (53)` and macOS `1.0.7
  (62)` were archived from public source commit `515bd93`, passed their release,
  security, privacy, signing, and dSYM checks, and were accepted for processing
  by App Store Connect at 19:15 and 19:18 CEST. Apple then marked both uploads
  complete, made builds `53` and `62` ready to test, and assigned them to the
  internal `Tune AV Test` group. macOS `62` was automatically installed and its
  signed-in Pro cold launch passed the no-feedback-read gate. Neither build was
  submitted to App Review. Install iOS `53` and complete the remaining focused
  physical traffic gate before promotion.

- Product-scope decision, 2026-07-13: TestFlight iOS `1.0.7 (52)` and macOS
  `1.0.7 (61)` still contain the superseded feedback bootstrap/restore contract
  and user-facing copy. Their saved-radio and saved-song traffic evidence is
  valid, but neither build is the final App Review candidate. Submit only a
  later build that implements [the approved scope](pro-sync-scope.md) and passes
  the focused migration gates.

- TestFlight delivery checkpoint, 2026-07-10: iPhone/iPad `1.0.7 (46)` and
  macOS `1.0.7 (55)` were accepted for processing by App Store Connect from
  public commit `1f65bc0`. Both passed final archive and privacy validation and
  include bounded Pro realtime-session renewal. Processing completion and
  tester-group availability remain to be confirmed; neither delivery is an App
  Review submission.
- iPhone/iPad approved baseline: `1.0.5 (44)` per 2026-07-03 operator report.
- macOS approved baseline: `1.0.5 (47)` per 2026-07-03 operator report.
- iPhone/iPad `1.0.6 (45)` was uploaded to App Store Connect and submitted to
  App Review on 2026-07-03 per operator report; approval is pending. It carries
  the Sentry diagnostic filter for expected unavailable promo-code responses.
- macOS `1.0.6 (49)` was uploaded to App Store Connect and submitted to App
  Review on 2026-07-03; approval is pending. Review submission id:
  `5e5d7cdb-7827-4472-ae9f-f737dd92fb24`. It carries the Music history
  list-source fix, macOS radio-library regression coverage, and contextual
  macOS Avi navigation. App Store Connect rejects new `1.0.5` builds after the
  approved `1.0.5 (47)` train, so macOS must use the next marketing version for
  TestFlight submissions. The previous macOS `1.0.6 (48)` package was uploaded
  to App Store Connect on 2026-07-03 before the contextual Avi navigation
  update.
- Previous cross-platform baseline: iOS/iPadOS `1.0.4 (42)` and macOS
  `1.0.4 (45)` were approved on 2026-07-02 per operator report.
- The current approved maintenance build keeps the Account/Tune AV Pro state in
  a loading state until the latest account access refresh completes.
- macOS App Store first release review used the same Tune AV app record and was
  submitted after the build, metadata, subscription setup, manual release
  setting, screenshots, and macOS TestFlight Pro purchase/restore visibility
  checks were completed in App Store Connect.
- iOS public release notes can stay generic for this maintenance release, for
  example `Bug fixes.`.
- macOS is a first platform release. Do not use maintenance-release language such
  as `Bug fixes.` for macOS. Use first-release product copy such as
  `Tune AV is now available on Mac.` where App Store Connect asks for
  promotional text or release copy.
- macOS release preview v1 screenshots are prepared locally in
  `docs/app-store/screenshots/macos/`:
  `01-home.png`, `02-search.png`, `03-music.png`, `04-library.png`, and
  `05-profile.png`.
- The prepared macOS screenshot assets are `1440 x 900` PNGs and should be
  kept locally as the release preview v1 source assets. They are intentionally
  local/ignored release assets, not public-source files.

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
- Confirm macOS metadata does not imply Intel support while the release target is
  Apple Silicon-only.

Apple references:

- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [App Review preparation](https://developer.apple.com/distribute/app-review/)
