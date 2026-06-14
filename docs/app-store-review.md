# App Store Review Notes

Use this public checklist before attaching a new iOS or macOS build to App Store
review. Keep private credentials, reviewer accounts, provisioning details, and
approval records outside this repository.

## Release Scope

- Tune AV Pro sync covers saved stations, saved songs, station feedback, and song
  feedback for signed-in Pro accounts.
- Recents, discovery history, playback state, and device settings are local-only.
- iOS and macOS should be tested together with the same signed-in Pro account
  before submission.
- macOS is currently Apple Silicon-only while the Convex Swift binary dependency
  does not include an Intel macOS slice.

## Suggested What's New

Tune AV Pro now keeps saved radios, saved songs, and Avi feedback in sync across
iPhone and Mac. This update also improves sync reliability and keeps local
feedback safer during startup.

## Suggested Review Notes

Tune AV uses Account AV sign-in and Tune AV Pro for cloud sync. With a signed-in
Pro account, saved radios, saved songs, station feedback, and song feedback sync
between iOS and macOS. Recents, discovery history, playback state, and device
settings remain local to each device by design.

If a reviewer account is needed, provide it only in App Store Connect review
notes or private release operations, never in this public repository.

## Metadata And Legal Checks

- App Store privacy answers must cover the app's data practices across iOS and
  macOS, including third-party partners and any data linked to the account.
- Confirm the privacy policy and App Store privacy labels describe account-linked
  product interaction or preference data if saved radios, saved songs, or
  feedback are collected for sync, personalization, analytics, or support.
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
