# Delivery checks

Octopus is distributed as a local agent plugin through its supported host
marketplaces and packaged repository. The existing release and installation
contract is in [RELEASING.md](../RELEASING.md#delivery-contract-for-workflow-methods).
This document adds checks for Codex listing and first-use changes.

## Model catalog checks

For model IDs, capabilities, pricing or default-route changes, run:

```bash
bash tests/unit/test-model-catalog-refresh.sh
bash tests/unit/test-opencode-model-defaults.sh
bash tests/unit/test-shipped-state-model-resolution.sh
bash tests/unit/test-resolve-model.sh
bash tests/unit/test-cost-pricing.sh
make sync
make ci-quick
```

Verify provider IDs, current public availability, limits and prices against
first-party listings. Preserve saved user pins. Record free-access terms and
paid-route changes. Offline checks do not establish account entitlement or
successful authenticated inference.

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
