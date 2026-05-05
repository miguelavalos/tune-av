# Private Config And Infisical

This repository is public and open source. Anything committed here can become public, so production login, Pro, hosted backend, signing, and account-management config must never be hardcoded in tracked files.

## Rules

1. Do not commit `apps/ios/Config/Local.xcconfig` or `apps/macos/TuneAVMac/Config/Local.xcconfig`.
2. Do not commit `.env`, `.env.*`, `.infisical/bootstrap.env`, signing files, provisioning profiles, keystores, or generated build output.
3. Do not commit real Clerk keys, store billing secrets, backend tokens, subscription sync tokens, or private service credentials.
4. Do not add production backend URLs as fallback constants in source or scripts. Production values must come from Infisical.
5. Do not add public example secret files either. Keep bootstrap examples and generated config examples in private Avalsys infrastructure, not here.

## Generate Config

Local development:

```bash
bun install
bun run ios:config
```

The command resolves through the shared avalsys workspace bootstrap at `../../.infisical/bootstrap.env` by default. This public repository should not contain `.env.example`, `.infisical/bootstrap.env`, `.infisical/bootstrap.env.example`, or generated local config examples.

Production/App Store preparation:

```bash
bun run ios:config:production
```

The production command must fail if Infisical does not provide required values.

## Before Pushing

Run this from the repository root:

```bash
bun run config:hygiene
```

If this finds a real production value or forbidden config artifact in a tracked file, remove it before pushing. If a real secret was already pushed, rotate it in the provider and clean the Git history.
