# Tune AV

Open-source native client repo for Tune AV.

This repository contains the active SwiftUI iOS and macOS clients, shared Apple
UI code, local playback, local persistence, public assets, and frontend
documentation.
Non-public service operations, release operations, signing material, service
configuration, and approval records do not belong in this repo.

Before validating signed account, subscription, purchase, backend, or deletion
workflows, read [AGENTS.md](AGENTS.md). Those workflows are governed by private
AVALSYS runbooks and must not be replaced with an invented local backend flow.

The current Apple clients are `apps/ios` and `apps/macos`. iOS remains the
primary mobile target; macOS shares the same product behavior where practical
and uses native macOS presentation differences.

## License

This repository is released under the MIT license. See [LICENSE](LICENSE).

## Repository Shape

```text
apps/
  ios/      SwiftUI iOS app
  macos/    SwiftUI macOS app, Apple Silicon release target
  web/      TanStack web app for signed-in Tune AV surfaces
docs/
  ios-current-state.md
  ios-animation-and-assets.md
  install.md
  release-checklist.md
shared/
  apple/     Swift modules shared by Apple targets
  contracts/ Platform-neutral client contracts when needed
```

## What Is Included

- local-first listening experience
- local-first playback, recents, automatic discoveries, and on-device settings
- configurable external public-info and lyrics search engine on web/iOS
- Pro cloud sync for explicitly saved stations and explicitly saved songs
- optional Pro feedback upload for server-side summaries and recommendations;
  feedback is not restored across devices
- optional account and premium UI surfaces when local configuration enables them
- iOS project and public Xcode configuration
- shared SwiftUI shell, branding, settings, Avi, and text-fit helpers
- macOS project and public Xcode configuration for Apple Silicon builds

## Current State

- `apps/ios` is the current Tune AV iOS app.
- `apps/macos` is the current Tune AV macOS app. The macOS release target is
  Apple Silicon-only while the current Convex Swift binary dependency does not
  provide an Intel macOS slice. App Store release builds use the same
  `com.avalsys.tuneav` bundle identifier as iOS because macOS is added as a
  platform on the existing App Store Connect app record.
- `apps/web` is the current Tune AV web app for signed-in app surfaces.
- `shared/apple` is the shared Swift implementation root for Apple-domain UI
  behavior.
- `shared/contracts` is reserved for platform-neutral client contracts.
- User library storage is local by default.
- Recents, discovery history, playback state, and device settings remain
  local-only unless a future public contract says otherwise.
- Network-backed and premium behaviors are optional, configuration-gated, and
  documented publicly only at the client-behavior level.

Use [docs/pro-sync-scope.md](docs/pro-sync-scope.md) as the authoritative public
Pro sync contract. Use [docs/ios-current-state.md](docs/ios-current-state.md) for
the wider Apple client behavior and verification state.

## Local Setup

### iOS

1. Install repo tooling:
   `pnpm install`
2. If your local build needs private runtime values, create
   `apps/ios/Config/Local.xcconfig` outside git.
3. Open `apps/ios/TuneAV.xcodeproj` in Xcode and run the `TuneAV` scheme.

The tracked debug configuration uses neutral defaults and optional
`Local.xcconfig` overrides.

### macOS

1. Install repo tooling:
   `pnpm install`
2. If your local build needs private runtime values, create
   `apps/macos/Config/Local.xcconfig` outside git.
3. Open `apps/macos/TuneAVMac.xcodeproj` in Xcode and run the `TuneAVMac`
   scheme.

The macOS target is configured for Apple Silicon builds.

## Local Secrets

This public repo does not carry private bootstrap examples or generated local
config.

- Private bootstrap material belongs outside this public repository.
- Generated native local files stay local-only.
- Do not add `.env.example`, bootstrap examples, or example secret files.
- Keep non-public operations and planning material in private repositories.

Run `vp run config:hygiene` before pushing config-related changes.

See [docs/install.md](docs/install.md) for setup details.

For playback-adjacent UI and Avi asset work, follow
[docs/ios-animation-and-assets.md](docs/ios-animation-and-assets.md).

## Third-Party Data Shown In The Client

- Station discovery can show public radio-directory data.
- Playback uses direct third-party station stream hosts that Tune AV does not
  control.
- Public metadata can provide factual station and now-playing context.
- Do not treat public metadata logos, favicons, station artwork, platform
  logos, or other brand imagery as automatically display-safe. Use
  product-owned/generated placeholders or reviewed rights evidence.
- Tune AV's station-logo restriction should not be generalized into a blanket
  ban on TV/movie posters in other Apps AV products when provider terms support
  title-reference poster use.

Public docs should describe only the client behavior that users and contributors
can see or test locally.

## Contributing And Security

- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security policy: [SECURITY.md](SECURITY.md)
- Support policy: [SUPPORT.md](SUPPORT.md)
- Current iOS state: [docs/ios-current-state.md](docs/ios-current-state.md)
- Client checklist: [docs/release-checklist.md](docs/release-checklist.md)
