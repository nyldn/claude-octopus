# Claude Octopus tests

Use the smallest gate that proves the change while you work. Run the complete
local gate before merge or release.

## Commands

```bash
# Once per clean checkout, install adapter build/runtime dependencies.
make test-deps

# Select focused suites from the files changed on this branch.
make ci-changed

# Match the complete local release gate: generated files, smoke, unit, integration.
make ci-local

# Run one suite while iterating.
./tests/run-all-tests.sh --suite=unit/test-ci-changed.sh

# List a category without running it.
./tests/run-all.sh unit --list
```

`make test` runs smoke and unit tests. `make test-all` adds integration tests.
Neither command runs live provider tests.
`make test-deps` needs npm registry access; subsequent adapter tests build and
execute locally. CI performs this setup before unit and symlink-path suites.

## Categories

| Category | Purpose | Command |
| --- | --- | --- |
| `smoke` | Fast syntax, metadata, registration, and safety checks | `make test-smoke` |
| `unit` | Hermetic behavior and contract tests | `make test-unit` / `make test-unit-deep` |
| `integration` | Cross-component workflows with local fixtures | `make test-integration` |
| `root` | Legacy suites still awaiting relocation or retirement; not a CI gate | `make test-root` |
| `live` | Opt-in checks that may invoke installed providers and incur cost | `make test-live` |

The main runner also supports `--fail-fast`, repeatable `--suite=PATH` and
`--exclude=PATH`, and deterministic `--shard-index=N --shard-count=N` flags. Run
`./tests/run-all-tests.sh --help` for the current interface.

## Adding a test

Place `test-*.sh` directly in `tests/smoke/`, `tests/unit/`, or
`tests/integration/`. The runner discovers files automatically; do not add a
manual runner entry.

A normal shell suite should:

1. Start with `set -euo pipefail`.
2. Source `tests/helpers/test-framework.sh`.
3. Call `test_suite`, then use `test_case`, `test_pass`, and `test_fail`.
4. Put state under `TEST_TMP_DIR`, including temporary `HOME` or workspace
   configuration, and remove it on exit.
5. Stub provider detection and execution. Hermetic categories must not call a
   live model, read a developer credential, or depend on an installed provider
   CLI.
6. Keep the script executable. Local test runs can alter fixture mode bits, so
   check `git diff --summary` before committing.

Prefer assertions on observable behavior. Static source checks are appropriate
for wiring and generated-file contracts, but they should not duplicate a
behavior test or claim that model output is deterministic.

## Choosing the final gate

`make ci-changed` fails closed to `make ci-local` when a shared, generated,
manifest, or unmapped file changes. A focused pass is enough for ordinary
branch pushes when the selector remains focused. Before merge or release, run
`make ci-local` regardless of the focused result.

`make test-unit` is the core unit lane used for fast feedback and ordinary CI;
it excludes the slow council lifecycle contract, whose public CLI contracts are
covered by smoke tests on every heavy run. `make test-unit-deep` restores the
complete unit suite, and `make ci-local` uses that complete lane before merge
or release. Ordinary pull requests use the changed-surface selector on one
Linux runner; shared CI, runner, generator, and orchestration changes fail
closed to the cross-platform core matrix. Main, scheduled, manually dispatched,
and merge-queue runs add the explicit deep council lane. Smoke, portability,
packaging, symlink, and integration checks remain separate gates because they
exercise different plugin contracts. This keeps routine plugin changes fast
without making deep validation optional for release-quality runs.

Live tests are never part of the default or required matrix. Run them only when
the change requires real-provider evidence and you intend to spend the
associated quota.
