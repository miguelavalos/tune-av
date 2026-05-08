# Release Checklist

Use this checklist before creating a public GitHub release.

## Repository Hygiene

1. Run `bun install`.
2. Run the public hygiene check:

   ```bash
   bun run config:hygiene
   ```

3. Confirm no generated config files are present:
   - `apps/ios/Config/Local.xcconfig`
   - `apps/macos/Config/Local.xcconfig`
   - `.env`
   - `.env.*`
   - private bootstrap files
4. Confirm no signing files, provisioning profiles, private keys, exported certificates, or local build products are present.
5. Confirm public docs do not contain private email addresses, personal account names, Team IDs, local backend URLs, provider secrets, or operator runbooks.

## Build Verification

1. Generate Xcode projects when `project.yml` changes:

   ```bash
   cd apps/ios && xcodegen generate
   cd ../macos && xcodegen generate
   ```

2. Run iOS unit tests:

   ```bash
   cd apps/ios
   xcodebuild test -project TuneAV.xcodeproj \
     -scheme TuneAV \
     -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
     -only-testing:TuneAVTests \
     CODE_SIGNING_ALLOWED=NO
   ```

3. Run macOS tests:

   ```bash
   cd apps/macos
   xcodebuild test -project TuneAVMac.xcodeproj \
     -scheme TuneAVMac \
     -destination 'platform=macOS' \
     CODE_SIGNING_ALLOWED=NO
   ```

## Public Release

1. Update `CHANGELOG.md`.
2. Confirm `README.md`, `CONTRIBUTING.md`, `SUPPORT.md`, and `SECURITY.md` describe only public workflows.
3. Create a version tag only after build, tests, and hygiene checks pass.
4. Attach only public artifacts. Do not attach local config, signing output, archives containing provisioning profiles, or logs with account data.

## Private Operations

Store portal plans, provider setup, signing steps, production config, account-platform smoke tests, and review-response material outside this public repository.
