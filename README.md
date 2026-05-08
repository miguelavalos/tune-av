# Tune AV

Open-source native product repo for Tune AV.

This repository contains the active Tune AV iOS and macOS clients together with shared Apple-domain code, local playback and persistence flows, and account-facing UI. Private release operations, production configuration, signing material, and account platform infrastructure live outside this repository.

The current product targets are `iOS` and `macOS`.

When configured by the app operator, the Apple clients can resolve signed-in access from Account AV while remaining local-first by default.

## License

This repository is released under the MIT license. See [LICENSE](LICENSE).

## Repository Shape

```text
apps/
  ios/      SwiftUI iOS app
  macos/    SwiftUI macOS app for Mac App Store distribution
docs/
  install-ios.md
  install-macos.md
  release-checklist.md
shared/
  apple/     Swift Modules and Apple-domain shared code
  contracts/ Platform-neutral contracts reserved for client parity
```

## What Is Included

- local-first listening experience
- favorites, recents, and on-device settings
- account and premium UI surfaces
- iOS and macOS projects and Xcode configuration

## Current state

- `apps/ios` is the submitted first App Store client
- `apps/macos` is active again and targets Mac App Store parity with iOS
- `shared/apple` is the shared Swift implementation root for Apple-domain behavior
- `shared/contracts` is reserved for platform-neutral contracts when a non-Apple consumer exists
- the repo remains local-first overall, and account-platform adoption is intentionally narrow
- current product focus is App Store distribution for `tune-av iOS` and `tune-av macOS`

## Local Setup

### iOS

1. Install repo tooling:
   `bun install`
2. If you need signed account features, create `apps/ios/Config/Local.xcconfig` outside git with values from your own private operator configuration.
3. Open `apps/ios/TuneAV.xcodeproj` in Xcode and run the `TuneAV` scheme.

The tracked debug configuration uses neutral defaults and optional `Local.xcconfig` overrides.

### macOS

1. Install repo tooling:
   `bun install`
2. If you need signed account features, create `apps/macos/Config/Local.xcconfig` outside git with values from your own private operator configuration.
3. Open `apps/macos/TuneAVMac.xcodeproj` in Xcode and run the `TuneAVMac` scheme.

## Local Secrets

This public repo does not carry private bootstrap examples or generated local config.

- private bootstrap material belongs outside this public repository
- generated native local files stay local-only
- do not add `.env.example`, bootstrap examples, or example secret files to this public repo

Run `bun run config:hygiene` before pushing config-related changes.

See [docs/install-ios.md](docs/install-ios.md) and [docs/install-macos.md](docs/install-macos.md) for setup details.

## Platform integration

- Apple clients can use an operator-provided Account AV API base URL to refresh signed-in access.
- Cloud sync is available when account access enables it.
- Subscription/provider reconciliation is owned outside this public client repository; this client consumes the resulting access state.

## Third-Party Services And Data Sources

- Station discovery currently relies on `Radio Browser`.
- Playback relies on direct third-party station stream hosts that Tune AV does not control.
- Artwork resolution may use Apple `iTunes Search`.
- Favicon fallback resolution may use Google's favicon endpoint when station metadata does not provide a usable icon.
- Signed-in account and entitlement flows depend on operator-provided Account AV infrastructure.
- Public docs disclose the external station, stream, artwork, and account dependencies used by the app.

## Account Deletion Support

- Public deletion support URL: `https://tune-av.avalsys.com/delete-account`
- Local-only users can remove on-device data from inside the app or by deleting the app.
- If an Account AV was used, iOS and macOS provide native account safety flows that respect Account AV deletion eligibility, linked app, Pro access, and provider-subscription blockers. The public deletion page remains the support fallback.

## Pending work

1. Keep store/provider reconciliation owned outside the public client before enabling paid Pro surfaces.
2. Continue expanding product-specific cloud sync UX and conflict/merge handling across devices.
3. Run signed macOS QA for Account AV redirects and account deletion/app unlink against the intended operator environment.
4. Keep Apple-client access behavior aligned on account-owned capabilities.
5. Keep store disclosures aligned with the shipped account/deletion flow as production distribution expands.

## Contributing And Security

- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security policy: [SECURITY.md](SECURITY.md)
- Support policy: [SUPPORT.md](SUPPORT.md)
- Release checklist: [docs/release-checklist.md](docs/release-checklist.md)
