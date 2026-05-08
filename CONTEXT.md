# Tune AV Context

## Domain Terms

- **Tune AV**: the local-first radio listening product. The public repo owns native clients, local playback, local persistence, and public app configuration.
- **Account AV**: the account layer exposed to product surfaces when an operator configures signed-in features.
- **local mode**: the product-facing mode for a user without an Account AV connection. Data stays on the device.
- **connected account**: the product-facing mode for a signed-in free user. Identity is connected, but Tune AV library data remains local-only unless capabilities say otherwise.
- **pro**: the paid access mode. Pro may unlock account-owned features and cloud sync according to entitlement capabilities.
- **entitlement**: the account-owned resolution of plan tier, access mode, capabilities, and limits for one app and one user.
- **capability**: a specific permission derived from entitlement, such as cloud sync, account-platform use, premium features, or plan management.
- **library**: the user's Tune AV collection state, including favorites, recents, discoveries, saved tracks, and settings.
- **library snapshot**: a portable representation of library state used by Apple clients and library sync. It contains favorites, recents, discoveries, and settings without binding callers to SwiftData, UserDefaults, or backend storage.
- **library resource**: one independently versioned app data document inside library sync, such as `favorites`, `recents`, `discoveries`, or `settings`.
- **library sync conflict**: the state where a library resource changed remotely after the client last pulled it, requiring the product to refresh from cloud or explicitly keep this device.
- **app data**: account-stored per-user, per-app documents used for cloud sync.
- **library sync**: the workflow that compares local library state with app data, merges or rejects conflicting changes, and commits a new revision.

## Architectural Terms

- **Module**: anything with an interface and an implementation.
- **Interface**: everything a caller must know to use a Module correctly.
- **Adapter**: a concrete thing satisfying an interface at a seam.
- **Seam**: where behaviour can vary without editing the caller.
- **Locality**: change and verification concentrated in one Module.
- **Leverage**: more behaviour behind a smaller interface.

## Current Seams

- `public/tune-av/shared/apple` is the shared Apple Module for iOS and macOS behaviour.
- `public/tune-av/shared/apple/TuneAVLibrarySync.swift` owns the Apple library snapshot and library sync planning Interface. iOS SwiftData and macOS UserDefaults are Adapters at this seam.
- `public/tune-av/shared/contracts` holds public platform-neutral Tune AV contracts used to validate native client policy.
