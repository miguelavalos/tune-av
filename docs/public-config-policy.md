# Public Configuration Policy

Tune AV iOS is maintained in a public repository. Public code must not reveal private backend infrastructure.

## Do Not Commit

Never commit:

- Private backend base URLs.
- Preview, staging, or production backend hostnames.
- API keys, tokens, bootstrap credentials, team secrets, or provider secrets.
- Generated local config files.
- Operator-only runbooks that include private project identifiers.
- Local machine paths that reveal private infrastructure layout.

## Allowed In Public Code

Public code can contain:

- Public bundle identifiers.
- Public legal/support URLs.
- Public documentation that explains where configuration comes from.
- Environment variable names.
- Validation rules for URL shape, such as requiring `https`.
- Generic references to private local configuration.

Environment variable names are allowed because they describe the contract, not the secret value.

## iOS Runtime Configuration

iOS should read backend configuration from generated local settings, not hardcoded source constants.

Current rule:

- `ACCOUNTAV_API_BASE_URL` is read from bundle configuration.
- If the value is missing, backend-backed station search should fail closed or fall back to public catalog behavior where supported.
- The public repo should not contain a default private backend URL.

`apps/ios/Config/Local.xcconfig` is generated local output. It must stay untracked.

## Script Rules

Scripts may:

- Read private configuration from the local private environment.
- Generate local iOS config.
- Validate that production uses `https`.
- Reject obvious local, preview, or development values for production.

Scripts must not:

- Hardcode private backend hosts.
- Print secrets unless explicitly required for a local operator action.
- Write private values into tracked files.
- Treat generated local config as reusable documentation.

## Documentation Rules

Public docs should describe the process, not the private value.

Use wording like:

```text
Generated from local private config.
```

Do not document concrete private endpoints, tokens, project IDs, or dashboards in this repo.

## Review Checklist

Before commit or push:

```bash
git diff --check
git diff -U0 | rg '^\+.*(https?://api-|SECRET|TOKEN|PASSWORD)' || true
git grep -n 'api-account-av\|account-av-preview\|account-av\.avalsys' -- . || true
```

Expected result: no private backend endpoints or secrets in tracked files.

Public Tune AV legal/support URLs may still appear if they are intentionally user-facing.
