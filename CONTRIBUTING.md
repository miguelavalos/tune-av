# Contributing

## Scope

This repository contains the open-source iOS client for Tune AV.

Contributions are welcome for:

- SwiftUI UI improvements
- playback and local persistence behavior
- accessibility
- localization
- bug fixes
- documentation improvements

Please avoid proposing changes that assume access to private backend systems or internal platform infrastructure.

## Before Opening A PR

1. Keep changes focused and small when possible.
2. Make sure the app still builds locally.
3. Update docs if the setup or behavior changes.
4. Do not commit local config, secrets, or generated files.
5. Keep login, Pro, backend, signing, and release config outside this repository.

## Localization Rules

- The development language is English.
- All user-visible default copy must live in `apps/ios/TuneAV/Resources/en.lproj/Localizable.strings`.
- Translations must live in the matching locale files under `apps/ios/TuneAV/Resources/*.lproj/Localizable.strings`.
- Do not hardcode user-visible SwiftUI text in Swift files, including `Text`, `Button`, `Label`, navigation titles, sheet titles, empty states, cards, alerts, accessibility labels, and paywall copy.
- Swift code, comments, identifiers, and string keys must be English.
- Hardcoded strings in Swift are only acceptable for non-visible technical values such as SF Symbols, accessibility identifiers, persistence keys, cache keys, asset names, debug messages, test fixtures, and external provider data shown as returned.

## Pull Requests

- Use clear commit messages.
- Describe user-facing behavior changes.
- Mention any manual test steps you ran.
- If a change touches config or signing behavior, call that out explicitly.

## Issues

- Use issues for bugs, usability problems, and well-scoped feature requests.
- For security issues, do not open a public issue. Follow `SECURITY.md`.
