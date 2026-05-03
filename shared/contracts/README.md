# Shared Contracts

This folder is reserved for platform-neutral AV Tunesys contracts.

Use it only when a rule or data shape must be shared beyond Apple Swift code: iOS, macOS, backend, generated clients, tests, or release tooling.

## Current Contracts

- `access-policy.json`: canonical AV Tunesys access modes, plan tiers, capabilities, and per-mode limits. iOS validates its `AccessLimits` and `AccessCapabilities` Adapter against this file.

## Entry Criteria

Add files here when at least one of these is true:

- backend and one or more clients need the same schema or enum values
- Future non-Apple clients and Apple need the same fixture or generated input
- tests in multiple runtimes need the same canonical examples
- a release rule must be validated outside one app target

Avoid moving Apple-only Swift behavior here. Prefer `../apple/` until there is a real non-Apple consumer.
