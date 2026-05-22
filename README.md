# Tune AV

Open-source native product repo for Tune AV.

This repository contains the active Tune AV iOS client, shared Apple-domain code,
local playback, persistence flows, and public app configuration. Non-public
operational, signing, backend, subscription-dashboard, and release-evidence
material lives outside this repository.

The app to treat as current is `apps/ios`.

## License

This repository is released under the MIT license. See [LICENSE](LICENSE).

## Repository Shape

```text
apps/
  ios/      SwiftUI iOS app
  macos/    SwiftUI macOS app for Mac App Store distribution
docs/
  ios-current-state.md
  ios-animation-and-assets.md
  install.md
  release-checklist.md
shared/
  apple/     Swift Modules and Apple-domain shared code
  contracts/ Platform-neutral contracts reserved for client parity
```

## What Is Included

- local-first listening experience
- favorites, recents, and on-device settings
- optional account UI surfaces
- iOS project and public Xcode configuration
- secondary macOS files retained for future/parity work

## Current state

- `apps/ios` is the current Tune AV app
- `shared/apple` is the shared Swift implementation root for Apple-domain behavior
- `shared/contracts` is reserved for platform-neutral contracts when a non-Apple consumer exists
- the repo keeps user library storage local by default
- account, subscription, analytics, and cloud-sync behavior is optional and configuration-gated

Use [docs/ios-current-state.md](docs/ios-current-state.md) as the public source
of truth for the current iOS app.

As of 2026-05-22, Tune AV iOS is in App Store submission preparation. The
shared Apple foundation work for the first release candidate has been extracted
into `apps-av/apple`, the release preflight with archive evidence passes, and
the remaining work is operational: signed upload, TestFlight processing, final
App Review metadata, and real-device release smoke.

## Local Setup

### iOS

1. Install repo tooling:
   `bun install`
2. If your local build needs signing or account values, create `apps/ios/Config/Local.xcconfig` outside git.
3. Open `apps/ios/TuneAV.xcodeproj` in Xcode and run the `TuneAV` scheme.

The tracked debug configuration uses neutral defaults and optional `Local.xcconfig` overrides.

macOS files may exist in the repository, but macOS is secondary to the iOS app
for the current documentation and release flow.

## Local Secrets

This public repo does not carry private bootstrap examples or generated local config.

- private bootstrap material belongs outside this public repository
- generated native local files stay local-only
- do not add `.env.example`, bootstrap examples, or example secret files to this public repo
- keep non-public operational and planning material in private repositories

Run `bun run config:hygiene` before pushing config-related changes.

See [docs/install.md](docs/install.md) for setup details.

For playback-adjacent UI and Avi asset work, follow
[docs/ios-animation-and-assets.md](docs/ios-animation-and-assets.md).

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
- Current iOS state: [docs/ios-current-state.md](docs/ios-current-state.md)
- Release checklist: [docs/release-checklist.md](docs/release-checklist.md)
- Continuation plan: [docs/continuation-2026-05-22.md](docs/continuation-2026-05-22.md)
