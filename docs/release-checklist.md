# Release Checklist

Use this checklist before creating the first public GitHub release and before each later tagged release.

## Repository Hygiene

1. Run `bun install`.
2. Run `bun run config:hygiene`.
3. Confirm no generated config files are present:
   - `apps/ios/Config/Local.xcconfig`
   - `apps/macos/AvtunesysMac/Config/Local.xcconfig`
   - `.env`
   - `.env.*`
   - `.infisical/bootstrap.env`
4. Confirm no signing files, provisioning profiles, private keys, exported certificates, or local build products are present.
5. Confirm public docs do not contain private email addresses, personal account names, Team IDs, local backend URLs, or provider secrets.

## Build Verification

1. Regenerate local config outside git if needed:

   ```bash
   bun run ios:config
   ```

2. Build iOS for simulator:

   ```bash
   xcodebuild -project apps/ios/Avtunesys.xcodeproj \
     -scheme Avtunesys \
     -configuration Debug \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     build
   ```

3. Run focused tests when touching shared policy, access, or persistence behavior:

   ```bash
   xcodebuild -project apps/ios/Avtunesys.xcodeproj \
     -scheme Avtunesys \
     -configuration Debug \
     -destination 'platform=iOS Simulator,name=iPhone 17' \
     test
   ```

4. Remove generated local config again before publishing the repository state.

## GitHub Release

1. Update `CHANGELOG.md`.
2. Confirm `README.md`, `CONTRIBUTING.md`, `SUPPORT.md`, and `SECURITY.md` describe the current public workflow.
3. Create a version tag only after the build and hygiene checks pass.
4. Attach only public artifacts. Do not attach local config, signing output, archives containing provisioning profiles, or logs with account data.
