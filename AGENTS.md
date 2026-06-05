# Tune AV Agent Rules

This public repo does not define the full signed-runtime testing workflow.

For any native app workflow validation that touches signed account state,
subscriptions, purchases, RevenueCat identity, uploads, backend-owned library
state, deletion flows, or private API access, follow the private AVALSYS guides.
Do not invent a local runtime flow from this public repo.

- `private/avalsys-suite/docs/platform/native-preview-dev-validation-guide.md`
- `private/avalsys-suite/docs/tune-av/development-runbook.md`
- `private/avalsys-suite/docs/tune-av/public-repo-release-process.md`

Mandatory rules:

- use Cloudflare preview for signed API runtime;
- use Convex cloud `dev`, not local Convex, when a native app workflow depends
  on Convex-backed state;
- do not use `wrangler dev` or another local Worker as product app backend;
- do not invent alternate runtime/testing flows when the private guide already
  defines one;
- use Infisical/Varlock-backed private tooling for config, deploy keys, and
  secret resolution;
- keep private URLs, service identifiers, approval status, and operations
  evidence out of this public repo;
- treat Account AV provider session identity as session metadata only; product
  ownership and backend-owned state must resolve through the internal Apps AV
  account user contract.

If the private repo is unavailable, stop and say that the authoritative runbook
cannot be checked. Do not substitute a guessed local workflow.
