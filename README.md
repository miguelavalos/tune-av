# Tune AV

Open-source native client repo for Tune AV.

This repository contains the active SwiftUI iOS client, shared Apple UI code,
local playback, local persistence, public assets, and frontend documentation.
Non-public service operations, release operations, signing material, service
configuration, and approval records do not belong in this repo.

Before validating signed account, subscription, purchase, backend, or deletion
workflows, read [AGENTS.md](AGENTS.md). Those workflows are governed by private
AVALSYS runbooks and must not be replaced with an invented local backend flow.

The app to treat as current is `apps/ios`.

## License

This repository is released under the MIT license. See [LICENSE](LICENSE).

## Repository Shape

```text
apps/
  ios/      SwiftUI iOS app
  macos/    SwiftUI macOS app kept for parity work
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
- local-first favorites, recents, automatic discoveries, and on-device settings
- Pro cloud sync for explicitly saved stations and saved songs only
- optional account and premium UI surfaces when local configuration enables them
- iOS project and public Xcode configuration
- shared SwiftUI shell, branding, settings, Avi, and text-fit helpers
- secondary macOS files retained for future/parity work

## Current State

- `apps/ios` is the current Tune AV app.
- `shared/apple` is the shared Swift implementation root for Apple-domain UI
  behavior.
- `shared/contracts` is reserved for platform-neutral client contracts.
- User library storage is local by default.
- Network-backed and premium behaviors are optional, configuration-gated, and
  documented publicly only at the client-behavior level.

Use [docs/ios-current-state.md](docs/ios-current-state.md) as the public source
of truth for the current iOS app.

## Local Setup

### iOS

1. Install repo tooling:
   `bun install`
2. If your local build needs private runtime values, create
   `apps/ios/Config/Local.xcconfig` outside git.
3. Open `apps/ios/TuneAV.xcodeproj` in Xcode and run the `TuneAV` scheme.

The tracked debug configuration uses neutral defaults and optional
`Local.xcconfig` overrides.

macOS files may exist in the repository, but macOS is secondary to the iOS app
for current public documentation.

## Local Secrets

This public repo does not carry private bootstrap examples or generated local
config.

- Private bootstrap material belongs outside this public repository.
- Generated native local files stay local-only.
- Do not add `.env.example`, bootstrap examples, or example secret files.
- Keep non-public operations and planning material in private repositories.

Run `bun run config:hygiene` before pushing config-related changes.

See [docs/install.md](docs/install.md) for setup details.

For playback-adjacent UI and Avi asset work, follow
[docs/ios-animation-and-assets.md](docs/ios-animation-and-assets.md).

## Third-Party Data Shown In The Client

- Station discovery can show public radio-directory data.
- Playback uses direct third-party station stream hosts that Tune AV does not
  control.
- Artwork and favicon fallbacks can come from public metadata sources.

Public docs should describe only the client behavior that users and contributors
can see or test locally.

## Contributing And Security

- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security policy: [SECURITY.md](SECURITY.md)
- Support policy: [SUPPORT.md](SUPPORT.md)
- Current iOS state: [docs/ios-current-state.md](docs/ios-current-state.md)
- Client checklist: [docs/release-checklist.md](docs/release-checklist.md)
