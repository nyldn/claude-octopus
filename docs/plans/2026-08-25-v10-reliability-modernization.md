# Claude Octopus v10 Reliability Modernization Implementation Plan

**Goal:** Ship v10 with truthful execution, Setup and Doctor 2.0, Provider Registry 2.0, safe cancellation and recovery, reproducible run observability, and eval-driven Fable, Claude, and Codex routing.

**Architecture:** Add a schema-versioned run-contract layer between provider dispatch and existing status/event consumers. Keep legacy status fields as a compatibility projection while migrating synchronous, background, and workflow dispatch to typed transitions. Expand the existing provider registry instead of replacing it, and drive diagnostics, routing evidence, and failure-injection fixtures from the same contracts.

**Tech Stack:** Bash 3.2, JSON/JSONL, jq with documented fallbacks, Python 3 for deterministic fixture evaluation, Claude Code plugin manifests, Codex plugin manifests, Make, GitHub Actions, Beads.

**Estimated Time:** 28 implementation slices x 5-20 minutes plus complete CI, protected review, and release propagation.

## Prerequisites

- [ ] Work only in `/Users/chris/.codex/worktrees/claude-octopus-v10` on `feat/v10-reliability-contracts`.
- [ ] Confirm `HEAD` started at canonical `upstream/main` commit `bc76e7c8248c93cfc4ba621ac5421077710777d0`.
- [ ] Confirm the original `/Users/chris/git/claude-octopus-dev` dirty checkout remains untouched.
- [ ] Use Beads epic `oco-de9` and children `oco-de9.1` through `oco-de9.8` as the task system of record.
- [ ] Complete the baseline `make ci-local` run before production changes.
- [ ] Keep `.claude/session-intent.md` available for staged review.

## Contract Design

The new seat record is append-only JSONL. A snapshot groups records by `seat_id`
and retains the most recent transition plus the full terminal verdict.

```json
{
  "schema_version": "10.0",
  "run_id": "run-...",
  "seat_id": "sync-probe-codex-...",
  "transition": "validated",
  "status": "ok",
  "contribution": "eligible",
  "requested": {
    "provider": "codex",
    "model": "gpt-5.6-luna",
    "effort": "low"
  },
  "resolved": {
    "provider": "codex",
    "model": "gpt-5.6-luna",
    "effort": "low"
  },
  "execution": {
    "phase": "probe",
    "role": "researcher",
    "isolation": "workspace-write",
    "worktree": ""
  },
  "metrics": {
    "tokens_in": 120,
    "tokens_out": 80,
    "duration_ms": 900,
    "estimated_cost_usd": "0.0007"
  },
  "artifacts": {
    "output": ".../result.md",
    "stderr": ".../stderr.log",
    "diff": ""
  },
  "reason": "",
  "timestamp": "2026-08-26T00:00:00Z"
}
```

Allowed progress transitions are:

```text
planned -> starting -> authenticated -> running -> output_received -> validated -> contributed
```

Allowed terminal alternatives are:

```text
degraded | skipped | failed | timeout | cancelled
```

Only `contributed` with `contribution=eligible`, or `degraded` with a usable
artifact and `contribution=eligible-with-warning`, may enter synthesis.

## Task 1: Establish baseline and tracking

**Files:**
- Inspect: `Makefile`
- Inspect: `AI_AGENT_HANDOFF.md`
- Track: Beads epic `oco-de9`

**Step 1: Run the full baseline**

```bash
make ci-local
```

Expected: 16 smoke suites, all unit suites, all integration suites, sync checks,
and CI-only checks finish with zero failures. Existing documented platform skips
must be identified rather than counted as new coverage.

**Step 2: Verify isolation**

```bash
git status --short --branch
git -C /Users/chris/git/claude-octopus-dev status --short --branch
```

Expected: v10 worktree is clean before planning files; original checkout retains
its prior unrelated dirty state.

## Task 2: Challenge the contract tests with a low-cost independent model

**Files:**
- Review: this plan
- Create later: `tests/unit/test-run-contract-v10.sh`
- Create later: `tests/integration/test-v10-failure-injection.sh`

**Step 1: Dispatch the adversarial test review**

```bash
if ! scripts/helpers/check-providers.sh | grep -c '^codex:available$' >/dev/null; then
  printf '%s\n' 'BLOCKED: Codex unavailable or unauthenticated; run /octo:doctor providers.'
else
  set +e
  OCTOPUS_CODEX_MODEL=gpt-5.6-luna \
    "$HOME/.claude-octopus/plugin/scripts/orchestrate.sh" spawn codex \
    "Review docs/plans/2026-08-25-v10-reliability-modernization.md. Find missing failure scenarios, tests that could pass with a stub, and boundary conditions. Return findings only; do not edit files."
  CODEX_REVIEW_RC=$?
  set -e
  if [[ "$CODEX_REVIEW_RC" -ne 0 ]]; then
    printf '%s\n' 'BLOCKED: Codex dispatch failed authentication or did not produce a durable review artifact.'
  fi
fi
```

Expected: a real Codex dispatch artifact containing test-design findings. Verify
the artifact exists and has substantive output before accepting findings.

**Step 2: Apply only verified test-design findings to this plan**

Use `apply_patch`; do not change production code.

Verified findings to carry into the RED suites:

- Assert the complete JSONL record and snapshot schema, not only command status.
- Exercise every allowed terminal edge, reject every post-terminal transition,
  and prove rejected transitions leave the ledger byte-for-byte unchanged.
- Give every fixture an exact oracle: exit code, terminal transition, reason,
  provider call count, contribution verdict, and required artifacts.
- Assert requested identity before resolution, resolved identity afterward,
  distinct retry attempt IDs, and all legacy compatibility keys.
- Include zero-exit placeholder output, health failure, persistence failure, and
  normal Codex stdin closure after substantive output.
- Run the real entrypoint in a sanitized environment and prove no host provider
  or credential was consulted.

## Task 3: Write the run-contract RED tests

**Files:**
- Create: `tests/unit/test-run-contract-v10.sh`
- Test: `scripts/lib/run-contract.sh`

**Step 1: Add assertions for the public contract**

The test must assert:

```bash
run_contract_transition seat-1 planned
run_contract_transition seat-1 starting
run_contract_transition seat-1 authenticated
run_contract_transition seat-1 running
run_contract_transition seat-1 output_received output_file="$valid_output"
run_contract_transition seat-1 validated contribution=eligible
run_contract_transition seat-1 contributed contribution=eligible
```

After each transition, parse the last JSONL record with `jq -e` and assert the
schema version, run and seat identity, transition, status, contribution,
requested/resolved identity, execution metadata, artifacts, reason, and RFC
3339 timestamp. Assert `run_contract_latest_transition`,
`run_contract_output_usable`, `run_contract_contribution_eligible`, and
`run_contract_snapshot` against exact values so a no-op implementation cannot
pass.

It must also prove that a valid initial `planned` transition is accepted, then
reject invalid jumps without mutating the ledger:

```bash
run_contract_transition seat-2 contributed contribution=eligible
run_contract_transition seat-3 planned
run_contract_transition seat-3 starting
run_contract_transition seat-3 authenticated
run_contract_transition seat-3 running
run_contract_transition seat-3 output_received output_file="$empty_output"
run_contract_transition seat-3 validated contribution=eligible
run_contract_transition seat-4 planned
run_contract_transition seat-4 running
```

Cover every allowed terminal edge from the transition matrix, every terminal
state as an absorbing state, and duplicate terminalization. For each rejected
call, hash the ledger before and after and require an exact match.

**Step 2: Verify RED**

```bash
bash tests/unit/test-run-contract-v10.sh
```

Expected: failure because `scripts/lib/run-contract.sh` does not exist.

## Task 4: Implement the minimal run-contract library

**Files:**
- Create: `scripts/lib/run-contract.sh`
- Modify: `scripts/orchestrate.sh`

**Step 1: Add source-safe constants and validation**

```bash
OCTO_RUN_SCHEMA_VERSION="10.0"

octo_run_transition_valid() {
    local from="${1:-}" to="${2:-}"
    case "${from}:${to}" in
        :planned|planned:starting|starting:authenticated|authenticated:running|running:output_received|output_received:validated|validated:contributed) return 0 ;;
        planned:skipped|planned:failed|starting:failed|starting:cancelled|authenticated:failed|authenticated:cancelled|running:degraded|running:skipped|running:failed|running:timeout|running:cancelled|output_received:degraded|output_received:failed|output_received:cancelled|validated:degraded|validated:failed|validated:cancelled) return 0 ;;
        *) return 1 ;;
    esac
}
```

Implement `run_contract_transition`, `run_contract_latest_transition`,
`run_contract_output_usable`, `run_contract_contribution_eligible`, and
`run_contract_snapshot`. All file writes use destination-adjacent temporary
files and atomic rename; JSONL appends use the existing portable lock pattern.

**Step 2: Source it after workspace resolution dependencies and before dispatch**

Do not derive any workspace path at source time. Every path helper must resolve
`${WORKSPACE_DIR}` when called.

**Step 3: Verify GREEN**

```bash
bash tests/unit/test-run-contract-v10.sh
bash -n scripts/lib/run-contract.sh scripts/orchestrate.sh
```

**Step 4: Commit the slice**

```bash
git add scripts/lib/run-contract.sh scripts/orchestrate.sh tests/unit/test-run-contract-v10.sh
git commit -m "feat(runtime): add v10 seat execution contract"
```

## Task 5: Write RED tests for synchronous dispatch transitions

**Files:**
- Create: `tests/unit/test-agent-sync-run-contract.sh`
- Test: `scripts/lib/agent-sync.sh`

**Step 1: Add deterministic provider fixtures**

Cover success, auth exit, empty success, whitespace success, oversize rejection,
placeholder success, health failure, timeout, SIGSEGV recovery, normal Codex
stdin closure after substantive output, truncated output, and
persistence-unavailable paths.

Use an explicit scenario oracle table. For each fixture assert expected process
exit, exact transition sequence, terminal transition, reason classification,
provider invocation count, contribution verdict, synthesis eligibility, and
required/forbidden artifacts. Pre-dispatch failures must have zero provider
calls; ordinary dispatch exactly one; SIGSEGV recovery exactly two and never a
third. Force ledger append, directory creation, and atomic snapshot publication
failures. Each must terminate `failed`, forbid contribution, leave no dangling
temporary file, and expose the persistence error through the command exit and
stderr rather than silently degrading.

**Step 2: Verify RED**

```bash
bash tests/unit/test-agent-sync-run-contract.sh
```

Expected: failure because `run_agent_sync` has no typed transition integration.

## Task 6: Wire synchronous dispatch to the contract

**Files:**
- Modify: `scripts/lib/agent-sync.sh`
- Modify: `scripts/lib/error-tracking.sh`

**Step 1: Emit requested identity before model resolution**

Record `planned` with requested provider/model/effort and phase/role.

**Step 2: Emit resolved identity and health result**

Record `starting`, then `authenticated` only after the provider health/auth gate
passes. Provider-unavailable and auth failures terminate as `failed`.

**Step 3: Validate output before success**

Record `running`, `output_received`, `validated`, then `contributed`. Empty,
whitespace, placeholder, provider-rejection, or untrusted incomplete output
must not reach `contributed`.

**Step 4: Preserve compatibility**

Keep `write_agent_status` as a projection over the typed record. Add
`schema_version`, `seat_id`, `transition`, and `contribution` fields without
removing legacy `agent`, `role`, or `status` keys.

Tests must prove `planned` retains the requested provider/model/effort, later
records retain the resolved identity, recovery attempts receive distinct
attempt IDs under the same seat, and legacy status JSON keeps its complete
pre-v10 key set.

**Step 5: Verify GREEN**

```bash
bash tests/unit/test-agent-sync-run-contract.sh
bash tests/unit/test-agent-summary.sh
bash tests/unit/test-agent-sync-signal-retry.sh
```

**Step 6: Commit the slice**

```bash
git add scripts/lib/agent-sync.sh scripts/lib/error-tracking.sh tests/unit/test-agent-sync-run-contract.sh
git commit -m "feat(runtime): enforce truthful synchronous contributions"
```

## Task 7: Write and satisfy background dispatch contract tests

**Files:**
- Create: `tests/unit/test-spawn-run-contract.sh`
- Modify: `scripts/lib/spawn.sh`
- Modify: `scripts/lib/workflows.sh`

**Step 1: Verify RED for legacy and Agent Teams paths**

```bash
bash tests/unit/test-spawn-run-contract.sh
```

Cover successful external dispatch, Agent Teams result capture, hook-captured
output, provider exit, timeout, cancellation, and unusable result files.

**Step 2: Wire the same transitions**

Both paths must share `seat_id`, lifecycle ordering, identity metadata, and
contribution validation. Native host messages are dispatch evidence, not
completion evidence.

**Step 3: Verify GREEN and compatibility**

```bash
bash tests/unit/test-spawn-run-contract.sh
bash tests/unit/test-agent-lifecycle-events.sh
bash tests/unit/test-probe-cancellation-cleanup.sh
bash tests/unit/test-issue-947-pid-wait-window.sh
```

**Step 4: Commit the slice**

```bash
git add scripts/lib/spawn.sh scripts/lib/workflows.sh tests/unit/test-spawn-run-contract.sh
git commit -m "feat(runtime): unify background seat lifecycle"
```

## Task 8: Expand the Provider Registry RED tests

**Files:**
- Modify: `tests/unit/test-provider-registry.sh`
- Modify: `tests/unit/test-provider-registry-parity.sh`
- Test: `scripts/lib/provider-registry.sh`

**Step 1: Require registry-owned fields**

Add required fields for auth mode, health probe, detection probe, model env,
default model resolver, context ceiling, cost class, sandbox class, and
independence organization.

**Step 2: Reject duplicated provider ID case lists in shared consumers**

The test may allow provider-specific implementation functions, but identity and
capability selection must come from registry APIs.

**Step 3: Verify RED**

```bash
bash tests/unit/test-provider-registry.sh
bash tests/unit/test-provider-registry-parity.sh
```

## Task 9: Implement Provider Registry 2.0 metadata and adapters

**Files:**
- Modify: `scripts/lib/provider-registry.sh`
- Modify: `scripts/lib/provider-routing.sh`
- Modify: `scripts/lib/providers.sh`
- Modify: `scripts/lib/preflight.sh`
- Modify: `scripts/lib/dispatch.sh`
- Modify: `scripts/helpers/octo-model-config.sh`

**Step 1: Add fields without using associative arrays**

Preserve Bash 3.2. Use delimiter-safe rows or separate metadata functions.
Expose these APIs:

```bash
octo_provider_auth_mode PROVIDER
octo_provider_health_handler PROVIDER
octo_provider_detect_handler PROVIDER
octo_provider_model_env PROVIDER
octo_provider_context_tokens PROVIDER
octo_provider_cost_class PROVIDER
octo_provider_sandbox_class PROVIDER
```

**Step 2: Route shared decisions through the registry**

Provider-specific functions remain explicit and testable. Consumers select the
function or capability through registry metadata rather than parallel ID lists.

**Step 3: Verify GREEN**

```bash
bash tests/unit/test-provider-registry.sh
bash tests/unit/test-provider-registry-parity.sh
bash tests/unit/test-provider-availability-parity.sh
bash tests/unit/test-provider-health-probe.sh
bash tests/unit/test-dispatch-round-trip.sh
```

**Step 4: Commit the slice**

```bash
git add scripts/lib/provider-registry.sh scripts/lib/provider-routing.sh scripts/lib/providers.sh scripts/lib/preflight.sh scripts/lib/dispatch.sh scripts/helpers/octo-model-config.sh tests/unit/test-provider-registry.sh tests/unit/test-provider-registry-parity.sh
git commit -m "feat(providers): make registry authoritative"
```

## Task 10: Write Doctor and cache failure RED tests

**Files:**
- Create: `tests/unit/test-doctor-v10.sh`
- Modify: `tests/unit/test-cache-alignment.sh`
- Test: `scripts/lib/doctor.sh`
- Test: `scripts/lib/session.sh`
- Test: `scripts/lib/heuristics.sh`

**Step 1: Assert structured Doctor output**

Require:

```json
{
  "schema_version": "10.0",
  "summary": {"passed": 0, "warnings": 0, "failures": 1, "exit_code": 1},
  "results": []
}
```

Unknown flags and categories must return usage failure. A failed check must make
`doctor --json` exit nonzero while keeping stdout valid JSON.

**Step 2: Assert cache truth**

Source-time `WORKSPACE_DIR` absence must not produce `/.cache/probe-results`.
When cache creation or copy fails, synthesis remains usable but the UI must say
the result was not cached and the run manifest records the failure.

**Step 3: Verify RED**

```bash
bash tests/unit/test-doctor-v10.sh
bash tests/unit/test-cache-alignment.sh
```

## Task 11: Implement Setup and Doctor 2.0

**Files:**
- Modify: `scripts/lib/doctor.sh`
- Modify: `scripts/lib/config-display.sh`
- Modify: `scripts/lib/preflight.sh`
- Modify: `scripts/lib/plugin-update.sh`
- Modify: `commands/setup.md`
- Modify: `.claude/skills/skill-doctor/SKILL.md`
- Generated: `skills/skill-doctor/SKILL.md` via `make sync`
- Modify: `.claude-plugin/plugin.json` only if supported `userConfig` fields are required

**Step 1: Fix argument and exit semantics**

Parse known flags explicitly; reject unknown flags. `do_doctor` returns the
aggregated failure status after printing either JSON or human output.

**Step 2: Add guided checks and reversible repair proposals**

Detect loaded/cache version drift, strict plugin validation, provider auth and
model readiness, state/cache writability, stale running records, and orphan
process evidence. Repairs require explicit confirmation and use atomic writes.

**Step 3: Use supported plugin configuration only**

Keep secrets out of manifests and shell output. Store only safe defaults in
`userConfig`; continue using existing secure provider configuration paths.

**Step 4: Verify GREEN**

```bash
bash tests/unit/test-doctor-v10.sh
bash tests/unit/test-plugin-update-status.sh
bash tests/unit/test-provider-auth-validity.sh
bash tests/unit/test-command-registration.sh
```

**Step 5: Commit the slice**

```bash
git add scripts/lib/doctor.sh scripts/lib/config-display.sh scripts/lib/preflight.sh scripts/lib/plugin-update.sh scripts/orchestrate.sh commands/setup.md .claude/skills/skill-doctor/SKILL.md skills/skill-doctor/SKILL.md .claude-plugin/plugin.json tests/unit/test-doctor-v10.sh tests/unit/test-cache-alignment.sh
git commit -m "feat(setup): add fail-closed Doctor 2.0"
```

## Task 12: Fix probe cache truth with TDD

**Files:**
- Modify: `scripts/lib/session.sh`
- Modify: `scripts/lib/heuristics.sh`
- Modify: `scripts/orchestrate.sh`
- Test: `tests/unit/test-cache-alignment.sh`

**Step 1: Replace source-time path state with a helper**

```bash
octo_probe_cache_dir() {
    printf '%s\n' "${WORKSPACE_DIR:-$(resolve_octopus_workspace)}/.cache/probe-results"
}
```

All cache functions call the helper at execution time.

**Step 2: Return cache-write truth**

`save_to_cache` returns nonzero on mkdir, copy, or metadata failure.
`synthesize_probe_results` prints “Cached for 1 hour” only on zero; otherwise it
prints a non-fatal warning and records `cache.write.failed`.

**Step 3: Verify GREEN and original reproduction**

```bash
bash tests/unit/test-cache-alignment.sh
env -i HOME="$HOME" PATH="$PATH" bash -c 'source scripts/lib/session.sh; WORKSPACE_DIR=/tmp/octo-v10; octo_probe_cache_dir'
```

Expected path: `/tmp/octo-v10/.cache/probe-results`; never a root-owned path.

**Step 4: Commit the slice**

```bash
git add scripts/lib/session.sh scripts/lib/heuristics.sh scripts/orchestrate.sh tests/unit/test-cache-alignment.sh
git commit -m "fix(cache): report probe persistence truthfully"
```

## Task 13: Write safe cancellation and recovery RED tests

**Files:**
- Create: `tests/unit/test-v10-cancellation-recovery.sh`
- Test: `scripts/lib/spawn.sh`
- Test: `scripts/lib/agent-sync.sh`
- Test: `scripts/lib/workflows.sh`
- Test: `scripts/lib/run-contract.sh`

**Step 1: Inject process-tree failures**

Fixtures spawn a provider child and grandchild, cancel in the PID-assignment
window, cancel after output starts, interrupt during atomic publication, and
simulate a stale `running` record after process exit.

**Step 2: Verify RED**

```bash
bash tests/unit/test-v10-cancellation-recovery.sh
```

Expected: failures for missing terminal reconciliation or missing evidence.

## Task 14: Implement safe terminalization and checkpoints

**Files:**
- Modify: `scripts/lib/spawn.sh`
- Modify: `scripts/lib/agent-sync.sh`
- Modify: `scripts/lib/workflows.sh`
- Modify: `scripts/lib/run-contract.sh`
- Modify: `scripts/state-manager.sh`

**Step 1: Centralize process-tree cancellation**

Reuse the existing process-group and portable child enumeration mechanisms.
After TERM grace, KILL remaining descendants, verify absence, then write the
terminal contract record.

**Step 2: Persist inspection and resume data**

Record source SHA, dirty-source decision, worktree, output, stderr, diff
artifact, phase checkpoint, and terminal cleanup result. Resume may retry only
non-contributed seats and must create a new attempt ID.

**Step 3: Verify GREEN**

```bash
bash tests/unit/test-v10-cancellation-recovery.sh
bash tests/unit/test-probe-cancellation-cleanup.sh
bash tests/unit/test-council-pgrep-fallback.sh
bash tests/unit/test-crash-recovery.sh
```

**Step 4: Commit the slice**

```bash
git add scripts/lib/spawn.sh scripts/lib/agent-sync.sh scripts/lib/workflows.sh scripts/lib/run-contract.sh scripts/state-manager.sh tests/unit/test-v10-cancellation-recovery.sh
git commit -m "feat(runtime): terminalize cancelled and interrupted runs"
```

## Task 15: Write observability RED tests

**Files:**
- Create: `tests/unit/test-run-observability-v10.sh`
- Modify: `tests/unit/test-agent-summary.sh`
- Test: `scripts/lib/run-contract.sh`
- Test: `scripts/lib/usage-help.sh`

**Step 1: Require a reconstructable manifest**

Assert requested/resolved identity, effort, sandbox, worktree, timestamps,
tokens, estimated cost, artifact paths, phase status, contribution counts,
degraded coverage, terminal reason, and cleanup result.

**Step 2: Require status and explain commands**

`status --run RUN_ID --json` returns the manifest. `explain --run RUN_ID`
summarizes why seats contributed, degraded, skipped, or failed without rerunning
providers.

**Step 3: Verify RED**

```bash
bash tests/unit/test-run-observability-v10.sh
```

## Task 16: Implement the durable manifest and explain surface

**Files:**
- Modify: `scripts/lib/run-contract.sh`
- Modify: `scripts/lib/error-tracking.sh`
- Modify: `scripts/lib/usage-help.sh`
- Modify: `scripts/orchestrate.sh`
- Modify: `scripts/openclaw-status.sh` only if it consumes the legacy snapshot

**Step 1: Build snapshot atomically**

Write `runs/<run-id>/run.json` and update `runs/latest` only after a complete
snapshot exists. Preserve `agents.json` for compatibility.

**Step 2: Add read-only commands**

Status and explain must never perform auth probes or provider dispatch. They
read artifacts, validate schema, and return nonzero for unknown or corrupt runs.

**Step 3: Verify GREEN**

```bash
bash tests/unit/test-run-observability-v10.sh
bash tests/unit/test-agent-summary.sh
bash tests/unit/test-octo-state.sh
bash tests/unit/test-event-monitor.sh
```

**Step 4: Commit the slice**

```bash
git add scripts/lib/run-contract.sh scripts/lib/error-tracking.sh scripts/lib/usage-help.sh scripts/orchestrate.sh scripts/openclaw-status.sh tests/unit/test-run-observability-v10.sh tests/unit/test-agent-summary.sh
git commit -m "feat(observability): add reproducible v10 run manifests"
```

## Task 17: Write Fable and routing evaluation RED tests

**Files:**
- Create: `tests/unit/test-routing-evals-v10.sh`
- Modify: `tests/unit/test-fable5-escalation.sh`
- Modify: `tests/unit/test-fable5-mode.sh`
- Create: `data/routing/v10-eval-cases.json`
- Test: `scripts/lib/fable5.sh`
- Test: `scripts/lib/execution-profile.sh`

**Step 1: Add deterministic cases**

Include mechanical search, narrow repetitive edit, broad implementation,
architecture judgment, security review, same-family review, oversized Fable
prompt, refusal, quota exhaustion, explicit model pin, and cross-vendor verifier.

**Step 2: Define expected decisions**

Mechanical and narrow work resolve to Luna or Haiku class; balanced scans to
Terra or Sonnet class; premium judgment to Sol, Opus, or a single Fable seat.
User pins and project config retain precedence.

**Step 3: Verify RED**

```bash
bash tests/unit/test-routing-evals-v10.sh
bash tests/unit/test-fable5-escalation.sh
```

## Task 18: Implement auditable routing and Fable input gates

**Files:**
- Modify: `scripts/lib/fable5.sh`
- Modify: `scripts/lib/execution-profile.sh`
- Modify: `scripts/lib/model-resolver.sh`
- Modify: `scripts/lib/dispatch.sh`
- Modify: `docs/MODEL-ROUTING-STRATEGY.md`
- Add: `data/routing/v10-eval-cases.json`

**Step 1: Add the model-specific Fable gate**

```bash
fable5_prompt_within_budget() {
    local prompt_bytes="${1:-0}"
    local ceiling="${OCTOPUS_FABLE5_MAX_INPUT_BYTES:-524288}"
    [[ "$ceiling" =~ ^[0-9]+$ ]] || return 2
    [[ "$prompt_bytes" -le "$ceiling" ]]
}
```

Resolve the model before final dispatch and fail or fall back before invoking
Fable when the gate rejects the prompt. Record both requested and resolved
identity plus the reason.

**Step 2: Make routing policy evaluable**

Expose a pure `octo_route_task_class` and `octo_route_decision` interface whose
fixtures require no provider call. Keep explicit user/project pins highest.

**Step 3: Preserve independent review**

Fable and Opus count as one Anthropic family. A Fable judgment that requires
verification must select a non-Anthropic verifier or mark coverage degraded.

**Step 4: Verify GREEN**

```bash
bash tests/unit/test-routing-evals-v10.sh
bash tests/unit/test-fable5-escalation.sh
bash tests/unit/test-fable5-mode.sh
bash tests/unit/test-workflow-meta-contracts.sh
bash tests/unit/test-current-provider-model-defaults.sh
```

**Step 5: Commit the slice**

```bash
git add scripts/lib/fable5.sh scripts/lib/execution-profile.sh scripts/lib/model-resolver.sh scripts/lib/dispatch.sh docs/MODEL-ROUTING-STRATEGY.md data/routing/v10-eval-cases.json tests/unit/test-routing-evals-v10.sh tests/unit/test-fable5-escalation.sh tests/unit/test-fable5-mode.sh
git commit -m "feat(routing): add eval-backed Fable and Codex decisions"
```

## Task 19: Write the end-to-end failure-injection RED suite

**Files:**
- Create: `tests/helpers/v10-failure-fixtures.sh`
- Create: `tests/integration/test-v10-failure-injection.sh`
- Modify: `tests/run-tests.sh` only if automatic discovery needs it

**Step 1: Build isolated fixture providers**

The helper creates executable commands in a temporary `PATH` for:

```text
success | auth-fail | health-fail | exit-zero-empty | exit-zero-whitespace
exit-zero-placeholder | oversize | timeout | partial-then-timeout | child-tree
refusal | sigsegv-then-success | output-then-stdin-close | persistence-fail
```

Every fixture writes a private call ledger proving whether dispatch occurred.

**Step 2: Exercise the real entrypoint**

Run `scripts/orchestrate.sh` with temporary HOME, workspace, results, state,
provider config, and event log under `env -i` with only an explicit safe
allowlist. Clear every known credential variable and replace every provider and
health command reachable by the tested path. Never read host auth or make
network calls. The fixture ledger must prove that no unconfigured host provider
was invoked.

**Step 3: Assert failure truth**

For each scenario, consult a checked-in oracle table and assert exact command
exit, transition sequence, terminal state and reason, provider call count,
contribution eligibility, synthesis coverage, required and forbidden artifacts,
cleanup, cache message, and absence of live descendants. The
`output-then-stdin-close` case must finish successfully when substantive output
was durably captured; a normal closed stdin must not overwrite that result with
a false failure. The persistence case must fail closed with no synthesis input
and no dangling temporary files.

**Step 4: Verify RED**

```bash
bash tests/integration/test-v10-failure-injection.sh
```

Expected: at least one contract assertion fails before all v10 wiring is complete.

## Task 20: Make failure injection GREEN

**Files:**
- Modify only the production files implicated by failing scenarios
- Test: `tests/integration/test-v10-failure-injection.sh`

For every failure, follow systematic debugging:

1. Reproduce the exact scenario.
2. Trace its transition and process/file boundaries.
3. Compare with a passing fixture.
4. State one root-cause hypothesis.
5. Make one minimal fix.
6. Re-run the scenario, then the full failure-injection suite.

Stop after three failed fixes or a self-regulation score above 20 percent.

**Verification:**

```bash
bash tests/integration/test-v10-failure-injection.sh
```

Expected: every scenario passes, none skipped, no provider network calls.

**Commit:**

```bash
git add tests/helpers/v10-failure-fixtures.sh tests/integration/test-v10-failure-injection.sh scripts
git commit -m "test(e2e): inject v10 orchestration failures"
```

## Task 21: Add changed-scope mapping and run focused gates

**Files:**
- Modify: `tests/changed-scope.tsv`
- Modify: `tests/unit/test-ci-changed.sh`

**Step 1: Add audited mappings**

Map run-contract, Doctor, provider-registry, cancellation, observability, and
routing files to their focused suites. Shared orchestrator changes must still
fail closed to the full matrix.

**Step 2: Verify selection**

```bash
bash tests/unit/test-ci-changed.sh
scripts/ci-changed.sh --list upstream/main
```

**Step 3: Run proportional CI**

```bash
CI=true GITHUB_ACTIONS=true make ci-changed
```

Expected: selector chooses the complete matrix for shared v10 changes and all
selected suites pass.

## Task 22: Run sync and assembly validation

**Files:**
- Generated through: `make sync`

**Step 1: Regenerate from canonical sources**

```bash
make sync
make sync-check
python3 scripts/validate-plugin-assembly.py .
claude plugin validate . --strict
```

Expected: no generated drift after the check run and strict plugin validation
returns zero.

**Step 2: Verify file modes**

```bash
git diff upstream/main...HEAD --summary | grep "mode change"
```

Expected: no output and grep exit 1.

## Task 23: Run the complete local release matrix

**Files:** all changed files

```bash
make ci-local
bash scripts/validate-release.sh
git diff --check
git status --short --branch
```

Expected: zero failed suites, release validator success, no whitespace errors,
and only intended files changed.

## Task 24: Run staged specification and quality review

**Files:**
- Read: `.claude/session-intent.md`
- Review: `git diff upstream/main...HEAD`

**Step 1: Stage 1 specification review**

Check every Good Enough criterion and boundary from the intent contract against
code and fresh command evidence. Any failure blocks Stage 2.

**Step 2: Stage 2 code-quality review**

Run stub detection, then dispatch an independent Codex review of the exact diff.
Verify every finding against the current code before changing anything.

**Step 3: Remediate with RED-GREEN evidence**

Each accepted finding gets a failing regression before its fix. Re-run focused
tests and `make ci-local` after the last remediation.

## Task 25: Prepare v10 migration docs and changelog

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `README.md` canonical prose only
- Modify: `.claude-plugin/README.md` canonical prose only
- Modify: `PRODUCT.md` canonical prose only
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/DEVELOPER.md`
- Modify: `docs/PROVIDERS.md`
- Modify: `docs/MODEL-ROUTING-STRATEGY.md`
- Create: `docs/V10-MIGRATION.md`
- Modify: `AI_AGENT_HANDOFF.md`

Document the compatibility projection, new run schema, Doctor JSON, provider
registry ownership, cancellation behavior, status/explain commands, routing
eval policy, configuration defaults, and rollback instructions. Do not claim
release until live verification exists.

## Task 26: Create the release commit and PR

**Files:** release surfaces owned by `scripts/release.sh`

**Step 1: Prepare version 10.0.0**

```bash
scripts/release.sh 10.0.0 "Truthful execution, self-diagnosing setup, safe recovery, and eval-driven routing"
make sync
make ci-local
bash scripts/validate-release.sh
```

The release helper must not tag before the PR is squash-merged; if its current
mode combines preparation and publication, use its documented preparation path
or split the release PR as required by `RELEASING.md`.

**Step 2: Push and create the PR safely**

```bash
git pull --rebase upstream main
git push -u upstream feat/v10-reliability-contracts
```

Create PR body through a private file or `scripts/safe-gh-comment.sh`; never put
generated Markdown in inline shell arguments.

## Task 27: Verify and merge the protected head

For the exact PR head SHA:

- Required Smoke, Unit, and Integration checks pass.
- Independent review is approved.
- Every review thread is resolved.
- No failure-injection scenario is skipped.
- Branch is up to date with `main`.

Squash-merge only after all conditions are refreshed against the exact head.

## Task 28: Tag, publish, synchronize, and verify v10

**Step 1: Verify exact main merge commit**

```bash
git fetch upstream main
gh pr view PR_NUMBER --json state,mergeCommit
gh run list --branch main --commit MERGE_SHA
```

**Step 2: Tag and publish from the merge commit**

Follow `RELEASING.md` and `scripts/release.sh`. The annotated `v10.0.0` tag must
dereference to the squash-merge commit whose main Test Suite passed.

**Step 3: Synchronize the shared marketplace**

```bash
scripts/sync-shared-marketplace.sh
scripts/sync-shared-marketplace.sh --check
```

**Step 4: Verify fresh installations**

Use isolated temporary host homes. Verify Claude plugin install/list/validate,
Codex plugin discovery, `octo doctor --json`, one deterministic no-billing run,
status/explain reconstruction, update, and uninstall.

**Step 5: Close Beads and update handoff**

Close `oco-de9.1` through `oco-de9.8`, then `oco-de9`, only after live evidence.
Push Beads, update `AI_AGENT_HANDOFF.md`, and verify canonical branch/tag/release
and marketplace state.

## Completion Evidence Checklist

- [ ] Failure-injection suite: all scenarios passed, zero skipped.
- [ ] Focused unit suites: zero failures.
- [ ] `CI=true GITHUB_ACTIONS=true make ci-changed`: zero failures.
- [ ] `make ci-local`: zero failures after final code change.
- [ ] `bash scripts/validate-release.sh`: zero failures.
- [ ] Stage 1 spec compliance: all Good Enough criteria passed, all boundaries respected.
- [ ] Stage 2 quality review: no blocking findings.
- [ ] Exact PR head: required CI passed, approval present, zero unresolved threads.
- [ ] Exact squash-merge commit on `main`: Test Suite passed.
- [ ] `v10.0.0`: annotated tag and published GitHub release point at the merge commit.
- [ ] Shared marketplace reports `10.0.0`.
- [ ] Fresh Claude and Codex plugin verification passed.
- [ ] Original dirty checkout remains unchanged.
