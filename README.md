# Tune AV

Open-source native product repo for Tune AV.

This repository contains the active Tune AV iOS and macOS clients together with shared Apple-domain code, local playback, persistence flows, and public app configuration. Non-public operational and planning material lives outside this repository.

The current product targets are `iOS` and `macOS`.

## License

This repository is released under the MIT license. See [LICENSE](LICENSE).

## Repository Shape

```text
apps/
  ios/      SwiftUI iOS app
  macos/    SwiftUI macOS app for Mac App Store distribution
docs/
  ios-animation-performance.md
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
- optional account UI surfaces
- iOS and macOS projects and Xcode configuration

## Current state

- `apps/ios` is the submitted first App Store client
- `apps/macos` is active again and targets Mac App Store parity with iOS
- `shared/apple` is the shared Swift implementation root for Apple-domain behavior
- `shared/contracts` is reserved for platform-neutral contracts when a non-Apple consumer exists
- the repo keeps user library storage local by default

## Local Setup

### iOS

1. Install repo tooling:
   `bun install`
2. If your local build needs signing or account values, create `apps/ios/Config/Local.xcconfig` outside git.
3. Open `apps/ios/TuneAV.xcodeproj` in Xcode and run the `TuneAV` scheme.

The tracked debug configuration uses neutral defaults and optional `Local.xcconfig` overrides.

### macOS

1. Install repo tooling:
   `bun install`
2. If your local build needs signing or account values, create `apps/macos/Config/Local.xcconfig` outside git.
3. Open `apps/macos/TuneAVMac.xcodeproj` in Xcode and run the `TuneAVMac` scheme.

## Local Secrets

This public repo does not carry private bootstrap examples or generated local config.

- private bootstrap material belongs outside this public repository
- generated native local files stay local-only
- do not add `.env.example`, bootstrap examples, or example secret files to this public repo
- keep non-public operational and planning material in private repositories

Run `bun run config:hygiene` before pushing config-related changes.

See [docs/install-ios.md](docs/install-ios.md) and [docs/install-macos.md](docs/install-macos.md) for setup details.

For playback-adjacent UI work, follow [docs/ios-animation-performance.md](docs/ios-animation-performance.md).

## Third-Party Services And Data Sources

- Station discovery currently relies on `Radio Browser`.
- Playback relies on direct third-party station stream hosts that Tune AV does not control.
- Artwork resolution may use Apple `iTunes Search`.
- Favicon fallback resolution may use Google's favicon endpoint when station metadata does not provide a usable icon.
- Optional account-connected behavior is configuration-gated. Public docs should avoid operational service details.

## Account Deletion Support

- Public deletion support URL: `https://tune-av.avalsys.com/delete-account`
- Local-only users can remove on-device data from inside the app or by deleting the app.
- Account-connected deletion details are handled by private service operations. The public deletion page remains the support fallback.

## Contributing And Security

- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security policy: [SECURITY.md](SECURITY.md)
- Support policy: [SUPPORT.md](SUPPORT.md)
- Release checklist: [docs/release-checklist.md](docs/release-checklist.md)
