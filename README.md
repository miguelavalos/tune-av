# Tune AV

Open-source native product repo for Tune AV.

This repository contains the active Tune AV iOS client together with shared Apple-domain code, local playback and persistence flows, account-facing UI, and development-time premium/access configuration. Premium value, shared entitlement authority, and account platform logic live outside this repository.

The current product target is `iOS`.

When configured, the iOS client can resolve signed-in access from the shared Account AV backend while remaining local-first by default.

## License

This repository is released under the MIT license. See [LICENSE](LICENSE).

## Repository Shape

```text
apps/
  ios/      SwiftUI iOS app
docs/
  install-ios.md
  private-config-and-infisical.md
  release-checklist.md
shared/
  apple/     Swift Modules and Apple-domain shared code
  contracts/ Platform-neutral contracts reserved for backend/client parity
```

## What Is Included

- local-first listening experience
- favorites, recents, and on-device settings
- account and premium UI surfaces
- iOS project and Xcode configuration

## Current state

- `apps/ios` is still the most complete product client
- `apps/ios` is the current primary execution target
- checked-in non-iOS artifacts should be treated as inactive or exploratory unless explicitly reactivated
- `shared/apple` is the shared Swift implementation root for Apple-domain behavior
- `shared/contracts` is reserved for platform-neutral backend/client contracts when a non-Apple consumer exists
- the repo remains local-first overall, and platform/backend adoption is intentionally narrow
- current product focus is `tune-av iOS`

## Local Setup

### iOS

1. Install repo tooling:
   `bun install`
2. Resolve the local iOS config through the private Account AV Varlock + Infisical bootstrap:
   `bun run ios:config`
3. This writes `apps/ios/Config/Local.xcconfig` with the client-side values needed for your build.
4. Open `apps/ios/TuneAV.xcodeproj` in Xcode and run the `TuneAV` scheme.

For local signed builds, keep the real values out of git and regenerate local config through Varlock + Infisical when needed.

## Local Secrets

This public repo does not carry Infisical bootstrap examples or generated local config.

- private bootstrap material belongs outside this public repository
- generated native local files stay local-only
- native local files are generated through `varlock printenv`, not manual `infisical export` parsing
- do not add `.env.example`, bootstrap examples, or example secret files to this public repo

Run `bun run config:hygiene` before pushing config-related changes.

See [docs/install-ios.md](docs/install-ios.md) for setup details.

## Platform integration

- iOS can use `ACCOUNTAV_API_BASE_URL` to refresh signed-in access through `GET /v1/me/access`
- backend-backed app-data sync is available when account access enables cloud sync
- subscription/provider reconciliation is owned by the private Account AV backend; this public client consumes the resulting access state

## Third-Party Services And Data Sources

- Station discovery currently relies on `Radio Browser`.
- Playback relies on direct third-party station stream hosts that Tune AV does not control.
- Artwork resolution may use Apple `iTunes Search`.
- Favicon fallback resolution may use Google's favicon endpoint when station metadata does not provide a usable icon.
- Signed-in account and entitlement flows depend on the private Account AV backend and related identity infrastructure.
- Public docs disclose the external station, stream, artwork, and account dependencies used by the app.

## Account Deletion Support

- Public deletion support URL: `https://tune-av.avalsys.com/delete-account`
- Local-only users can remove on-device data from inside the app or by deleting the app.
- If an Account AV was used, the public deletion page documents the out-of-app request path and the provider-subscription caveats.

## Pending work

1. Keep store/provider reconciliation owned in private Account AV infrastructure before enabling paid Pro surfaces.
2. Continue expanding product-specific cloud sync UX and conflict/merge handling across devices.
3. Keep active Tune AV work focused on `iOS`.
4. Keep Apple-client access behavior aligned on backend-owned capabilities.
5. Keep store disclosures aligned with the shipped account/deletion flow as production distribution expands.

## Contributing And Security

- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security policy: [SECURITY.md](SECURITY.md)
- Support policy: [SUPPORT.md](SUPPORT.md)
- Release checklist: [docs/release-checklist.md](docs/release-checklist.md)
