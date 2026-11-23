# Delivery checks

Octopus is distributed as a local agent plugin through its supported host
marketplaces and packaged repository. The existing release and installation
contract is in [RELEASING.md](../RELEASING.md#delivery-contract-for-workflow-methods).
This document adds checks for Codex listing and first-use changes.

## Codex presentation checks

Run from the public repository root on a supported local macOS or Linux host:

```bash
bash scripts/build-codex-skills.sh --check
bash tests/unit/test-codex-manifest.sh
bash tests/unit/test-codex-plugin-icon.sh
bash tests/unit/test-codex-enforcement-detection.sh
bash scripts/test-codex-compat.sh
make ci-quick
npm pack --dry-run --json --ignore-scripts
```

Check that declared icon files and every registered skill are packaged. Preserve
skill identifiers, explicit invocation, provider credentials, project data and
host settings. Do not edit an installed cache or install a candidate into a live
user profile as part of these checks.

## Installed-host acceptance

Use an authorized test installation to verify the listing logo, full skill
phrases, skill details, and starter-prompt selection. First use must report
readiness before external dispatch and explain provider account costs. Record
the host version and plugin revision. Package checks and inert fixtures do not
prove Desktop rendering, model access, billing, or successful provider output.
If Desktop access is blocked, leave these acceptance checks explicitly pending.

Run deterministic checks before fresh review. Exact-commit hosted Smoke Tests,
Unit Tests and Integration Tests plus approval govern merge and release as
specified in the repository instructions. Publishing, installation and release
are separate authorized actions; passing these checks does not perform them.
