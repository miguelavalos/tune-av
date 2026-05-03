# Shared Code

This directory is the single root for code and contracts shared across AV Tunesys clients.

## Layout

- `apple/`: Swift Modules shared by the iOS and macOS apps. Code here may use Apple toolchains, Swift, and Foundation APIs.
- `contracts/`: Platform-neutral contracts, fixtures, schemas, or generated inputs that Apple clients, backend, future clients, or tooling can consume.
- `windows/`: Windows-specific shared code when Windows exists and needs shared implementation.

## Boundary

Do not put runtime-specific source directly under `shared/`. Create a platform or contract subfolder that states the intended consumers.

Use `shared/apple` for Swift implementation shared only by Apple targets. Move behavior to `shared/contracts` only when backend, generated clients, or future native clients need the same source of truth.

## Promotion Rules

Start from the iOS app unless there is already a stronger source of truth. Promote code only when it passes one of these checks:

- **Two-adapter check**: the behavior is used by at least two concrete Adapters, such as iOS and macOS, or iOS and backend contract generation.
- **Contract check**: the data shape or rule must stay identical across runtimes, releases, or generated clients.
- **Deletion test**: deleting the shared Module would make the same behavior reappear in multiple callers.

Do not promote code just because it may be useful later. One Adapter is usually a hypothetical seam.

## What Belongs In `shared/apple`

Use `shared/apple` for Apple-only Modules whose Interface is stable enough to be consumed by both iOS and macOS:

- station domain shape and station service parsing
- access policy limits and collection rules
- library snapshots, library resource records, and sync planning shared by iOS and macOS Adapters
- date/text/country normalization
- now-playing metadata parsing
- artwork and external-search URL construction

Keep SwiftUI views, app state, localization copy, StoreKit/UI flows, and app-specific orchestration in the app targets. If a shared Module needs localized text, pass localized strings in from the app Adapter rather than importing app localization.

## What Belongs In `shared/contracts`

Use `shared/contracts` for platform-neutral source of truth:

- JSON schema, OpenAPI fragments, or generated-client inputs
- cross-runtime fixtures used by tests in more than one target
- account/access/app-data shapes consumed by backend and clients
- documented limits or enum values that must match backend behavior

Contracts should not import Apple or backend runtime libraries. Keep them readable by generic tooling.

## Validation

When changing `shared/apple`:

1. Regenerate Xcode projects if files were added or removed:
   - `cd apps/ios && xcodegen generate`
   - `cd apps/macos/AvtunesysMac && xcodegen generate`
2. Run the focused iOS shared support tests.
3. Build the macOS target.

When changing `shared/contracts`, validate at least one consuming Adapter or generator in the same change. If no consumer exists yet, keep the contract as documentation or fixtures only.
