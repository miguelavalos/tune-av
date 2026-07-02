# Public Configuration Policy

Tune AV clients are maintained in a public repository. Public code and docs must
not reveal private infrastructure or operator-only details.

## Do Not Commit

Never commit:

- private base URLs;
- non-public hostnames;
- API keys, tokens, bootstrap credentials, team secrets, or service secrets;
- generated local config files;
- operator-only runbooks or private project identifiers;
- local machine paths that reveal private infrastructure layout;
- release, approval, distribution, or service-console status.

## Allowed In Public Code

Public code can contain:

- public bundle identifiers already required by the client project;
- public documentation that explains where configuration comes from;
- environment variable names;
- validation rules for URL shape, such as requiring `https`;
- generic references to generated local configuration.

Environment variable names are allowed because they describe the contract, not
the private value.

## Runtime Configuration

Native clients should read non-public runtime values from generated local
settings, not hardcoded source constants.

Runtime config separates platform and product backends:

- `ACCOUNTAV_API_BASE_URL` is the shared account/platform backend.
- `TUNEAV_API_BASE_URL` is the Tune product backend for `/v1/tune/*`.

Production config generation and runtime checks must reject local, development,
or preview-shaped values for either backend URL.

`apps/ios/Config/Local.xcconfig` and `apps/macos/Config/Local.xcconfig` are
generated local output. They must stay untracked.

Public-source hygiene and release-readiness are separate states:

- public-source hygiene expects generated local config files to be absent from
  the workspace before commit or push;
- release-readiness expects generated local config files to exist locally and be
  validated by the platform-specific release config hygiene scripts.

## Script Rules

Scripts may:

- read configuration from the local private environment;
- generate local native config;
- validate URL shape and required fields;
- reject obvious local or development values when the selected profile requires
  a different runtime shape.

Scripts must not:

- hardcode private hosts;
- print secrets;
- write private values into tracked files;
- treat generated local config as reusable documentation.

## Documentation Rules

Public docs should describe the process, not the private value.

Use wording like:

```text
Generated from local private config.
```

Do not document concrete private endpoints, tokens, project IDs, service
consoles, release status, approval status, service-console status, or distribution
evidence in this repo.

## Pre-Commit Check

Before commit or push:

```bash
git diff --check
vp run config:hygiene
```

Expected result: no private endpoints, secrets, generated config, or operations
material in tracked files.

If generated local config is present for a release build, run the relevant
platform release config hygiene command before archiving, then remove the local
generated files before public-source hygiene and commit checks.
