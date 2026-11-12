# Claude Octopus tests

Use affected behavioral checks while editing. Use the exact-commit hosted
gates for merge and release; keep full local runs for offline diagnosis.

## Commands

```bash
# Once per clean checkout, install adapter build/runtime dependencies.
make test-deps

# Before push, check generated artifacts and smoke.
make ci-quick

# Inspect the affected suites; run ci-changed when the plan is focused.
scripts/ci-changed.sh --list
make ci-changed

# Optional complete offline diagnosis: generated files, smoke, unit, integration.
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

## Test tiers

| Tier | When | Coverage |
| --- | --- | --- |
| Edit | Each behavior change | Affected regression suites with inert providers |
| Quick | Before push | `make ci-quick`: generated files, packaging, syntax, discovery, safety smoke |
| Focused PR | All changed paths have mappings | Affected unit suites on Linux and macOS, both smoke lanes, portability, path-sensitive suites, full integration |
| Full | Shared/unmapped PRs; every main, queue, nightly, manual run | Every unit suite, including council lifecycle, split into four weighted Linux shards and six weighted macOS shards; the other required checks also run |
| Native/artifact | Installation changes and publication | Isolated native installation/discovery, relevant first use, downloaded artifact and revision checks |
| Live | Explicit provider changes needing live evidence | Bounded opt-in provider checks, with quota and cost accounted for |

Required check names remain `Smoke Tests`, `Unit Tests`, and `Integration Tests`.
Their aggregate jobs reject failed, cancelled, skipped, or missing expected
coverage. Approval, zero unresolved review threads, an up-to-date branch, and
successful main CI for the squash commit remain mandatory. No successful
advisory/model output substitutes for these gates.

`make ci-changed` uses `tests/changed-scope.tsv`. Missing bases, stale mappings,
shared code, and unknown paths fail closed to `make ci-local`. Use the focused
plan for local feedback; don't repeat the full matrix locally when exact-commit
hosted coverage is available. `make ci-local` remains the complete offline
fallback. `make test-unit` keeps its historical core selection; the hosted full
tier and `make test-unit-deep` include council as part of the ordinary inventory.

The shard timing profile includes completed macOS suite measurements because
process-heavy tests can cost more there than on Linux. Unobserved suites retain
their previous weights. The profile changes shard membership; every unit suite
still runs once per OS. macOS has six lanes to leave room for the longer
suite durations measured on hosted runners; the 20-minute step limit stays
unchanged.

Integration runs alongside unit tests because it consumes no unit artifacts.
The symlink lane runs the explicit path-behavior set on every event. Packaging
already runs in smoke on both platforms, so there is no third standalone pack
job. Failed checks stay failed until repaired or a justified rerun succeeds;
an isolated passing rerun does not rewrite the earlier full-run result.

Focused and full unit steps run in an owned process group with a 20-minute
budget inside the 30-minute job. A timeout retains a bounded output tail and
fails the unit gate. External cancellation retains collected output, records
its signal, and cleans up owned children.
Failed or cancelled jobs upload the step log; the last named suite and test in
timeout output guide the repair.

Automatic Octopus multi-model PR reviews are opt-in through repository variable
`OCTOPUS_AUTOMATED_PR_REVIEW=true`. Manual and trusted comment commands remain
available. For a manual `review`, supply the PR number and use the prompt for
review context. It fetches the diff and invokes `code-review` without publishing
findings. This advisory workflow had unavailable verifier tooling and truncated
prompts, so its incomplete output cannot approve a release. The independent
approval requirement remains intact.

Refresh `tests/shard-weights.tsv` from successful timing evidence when the slow
suites change. Shards must be disjoint and their union must equal the discovered
inventory. New tests remain automatically discovered. Do not delete a regression
solely because it is slow; replace it only when equivalent behavioral coverage
is demonstrated.

Live tests are never part of the default or required matrix. Run them only when
the change requires real-provider evidence and you intend to spend the
associated quota.
