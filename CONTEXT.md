# Tune AV Context

## Domain Terms

- **Tune AV**: the local-first radio listening product. The public repo owns native clients, local playback, local persistence, and public app configuration.
- **Avi**: the Tune AV / Avalsys assistant name. All Avalsys and Tune AV product surfaces, docs, localization keys, and assistant copy must use Avi.
- **Eli**: the assistant name used in another Elisca project group. Do not use Eli in Avalsys or Tune AV product surfaces, even when conversation notes accidentally say Eli.
- **local library mode**: the storage mode where user-authored Tune AV library data stays on the device unless a private configuration enables account-connected behavior.
- **library**: the user's Tune AV collection state, including favorites, recents, discoveries, saved tracks, and settings.
- **library snapshot**: a portable representation of library state used by Apple clients and library sync. It contains favorites, recents, discoveries, and settings without binding callers to SwiftData, UserDefaults, or backend storage.
- **library resource**: one independently versioned app data document inside library sync, such as `favorites`, `recents`, `discoveries`, or `settings`.
- **library sync conflict**: the state where a library resource changed remotely after the client last pulled it, requiring the product to refresh from cloud or explicitly keep this device.
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
