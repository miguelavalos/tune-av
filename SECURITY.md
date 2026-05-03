# Security Policy

## Reporting A Vulnerability

Please do not report security vulnerabilities through public GitHub issues.

Use GitHub private vulnerability reporting for this repository when it is available. If private vulnerability reporting is not enabled yet, open a minimal public issue that only asks maintainers to enable a private reporting channel; do not include exploit details, secrets, logs, tokens, or personally identifying data in that issue.

Include the following details only in the private report:

- a short description of the issue
- affected files or features
- reproduction steps if available
- impact assessment if known
- whether credentials, account data, purchase state, or local user data can be exposed or modified

## Supported Versions

Until the first public release, only the default branch is considered supported for security review.

After public releases begin, supported versions will be documented in this file.

## Private Config

This is a public open-source repository. Do not commit production keys, local config, signing material, private backend URLs, provisioning profiles, generated local config, or provider credentials.

Login, Pro, hosted backend, and release values must come from local private configuration. See [`docs/private-config-and-infisical.md`](docs/private-config-and-infisical.md).
