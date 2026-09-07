# AI Agent Handoff

Last updated: 2026-09-07

Status: the five orchestrator review fixes from `a3f7847d` are prepared for
v11.2.1 on `release/v11.2.1`, tracking `oco-c3t`. Fix implementation task
`oco-v6s` is complete. Local verification and final code review passed.
The separate host-native automatic invocation investigation remains `oco-ml7`;
this change leaves hooks, host settings and implicit-invocation policy unchanged.

The last published version is v11.2.0, from main squash commit
`4febbb11a4e0c8e82574505ce1114dddbbd11d3f`. It includes engineering method
activation, independent review escalation and bounded engineering prototypes.
The release candidate updates version and marketplace metadata to v11.2.1.

Verified pushed checkpoint: `release/v11.2.1` matched
`upstream/release/v11.2.1` at `627c18cfafcdc90b45211e189564d7d5010b87c2`.
PR #1022 and its head SHA are the live source for later commits; a tracked file
cannot contain the SHA of its own commit. This checkpoint does not claim that
the subsequent native-cancellation changes are already pushed or published.

The user authorized the remaining lifecycle fix in `oco-x38`. Native signal
delivery now uses Linux PID handles or macOS audit tokens through one shared
helper. Ledger tokens reach that helper, and registration rejects hosts that
cannot support native cancellation before dispatch. Failure retains workflow
registrations for retry. Teardown no longer launches process probes or waits
the full grace period after workers exit. Duplicate shell tree traversal and
an unused verification wrapper were removed.

Focused verification passed native process control 20/20, orchestrator
regressions 33/33, Probe cancellation 21/21, Tangle cancellation 16/16,
background lifecycle 30/30, review aggregation 41/41 and PID capture 14/14.
The native suite completed in about 0.1 seconds on macOS. Package dry-run
includes both the ledger and shared process-control helpers with executable
modes. A fresh Astra high review returned `NO ACTIONABLE FINDINGS` after the
interruption, disappearing-process and failed-cleanup wait findings were fixed.
The new full local matrix passed all 16 smoke, 326 unit and 8 integration
suites. Final focused reruns cover the later review fixes. Contextual review
also passed 100/100. The docs suite passed 143/143 after removing obsolete
counters that printed a false failure section. Exact-head hosted checks and
approval are still required before merge.

The native-cancellation implementation was pushed as
`a4120376468a1591bdda8ec1f06dbacdb8e89132`. Hosted Ubuntu unit checks passed
all 325 ordinary suites, including 20 native process-control cases in 0.16
seconds. Both macOS unit shards passed as well. Integration checks were still
running at that checkpoint. A final shared PID-range guard rejects values
outside native signed `pid_t` before conversion. Its boundary regression failed
before the guard and passes afterward; native checks now pass 21/21 and
orchestration checks pass 33/33. A fresh review of this bounded final change
returned `NO ACTIONABLE FINDINGS`. Hosted checks must follow the final head.

Separate follow-up `oco-imu` records the hosted review's large truncated
specialist prompts and unavailable Codex verifier. Its PID-validation and
prefix-pruning warnings were checked against the implementation and rejected;
the shared validator and delimiter-qualified prune callers already cover them.

The next review follow-up batches Probe and Tangle ledger verification into
one interpreter invocation per workflow and retains verified tokens for native
signal binding. If a parent exits during descendant admission, cleanup reports
an incomplete result instead of claiming success or trusting a numeric PPID.
Regression fixtures publish child markers atomically, and the native test
wrapper uses the shared test framework. Focused Bash 3.2 checks passed 34/34
orchestrator, 21/21 Probe, 16/16 Tangle, 4/4 v10 recovery and 100/100 contextual
review cases. Native process-control checks passed 22/22. A fresh Astra high
review returned `NO ACTIONABLE FINDINGS`. The final full local matrix passed
all 16 smoke, 326 unit and 8 integration suites. Exact-head hosted checks and
approval remain required before merge.

Tracking: use the repository issue tracker and checked-in implementation
documentation as the source of truth. Do not put private checkout paths,
credentials, or host-specific state in this public handoff.

Next action: pass the release PR checks and review gate, squash-merge, verify
the exact main commit, then tag and publish v11.2.1 and sync the shared
marketplaces. Do not claim publication until those steps are verified.
Shared runtime changes retain the full local matrix.

Release preparation passed generated-file checks, README release sync 11/11,
release workflow regressions 11/11, all 16 smoke suites and plugin assembly
validation. A separate GPT-6 Astra high review of the metadata-only changes
returned `NO ACTIONABLE FINDINGS`. The README introduction no longer assigns
the original engineering-method additions to each new patch version.
The first hosted portability pass flagged the intentionally pre-expanded EXIT
trap under ShellCheck 0.9.0. A line-local SC2064 suppression documents why
Bash 3.2 requires the captured arguments; it changes no runtime behavior.

Hosted review on PR #1022 identified missing identity checks in workflow
cancellation. Probe, Tangle and scoped review cleanup now verify ledger
identities; active PID lists also require a current matching task registration.
Probe drops rejected PIDs before its later wait and heartbeat cleanup.
The worker-ownership pipeline consumes the full job listing under pipefail.
Concurrent-retirement coverage now removes an existing row, and CI-mode
coverage fails if its extracted initialization code is empty.
These regressions failed before correction. Focused checks passed 30/30
orchestrator cases, 21/21 Probe cancellation cases, 16/16 Tangle cancellation
cases, 100/100 contextual-review cases and 30/30 background lifecycle cases.
Hosted checks must be rerun on the final follow-up commit before merge.
The follow-up full local matrix passed all 16 smoke suites and 324/325 unit
suites. The remaining v10 cancellation fixture still wrote a legacy ledger row;
it now registers its real worker through the shared helper and passes 4/4.
The remaining live-worker marker fixture uses the same helper and passes 4/4.
All 8 integration suites passed after those fixture corrections. Production
code is unchanged from the final reviewed cancellation follow-up.

## Orchestrator review fixes

- Cancellation checks the worker's recorded process identity and skips legacy
  or stale entries. Workers register before spawn returns and retire their exact
  entry on exit. Registration, retirement and workflow pruning share one
  portable lock, preserving concurrent tasks.
- The legacy release command validates its arguments and delegates to
  `release.sh`, including its failure status. Dry-run never invokes the backend.
- Probe recovery reaches existing results and empty-directory guidance without
  failing an `ls` pipeline when no synthesis marker exists.
- Workflow summaries resolve provider, phase and role through the dispatch
  configuration, including Tangle coding and reasoning overrides.
- CI initialization preserves Jenkins, background-disabled hosts and explicit
  unattended mode.
- Focused checks passed: orchestrator regressions 16/16, workflow initialization
  6/6, background lifecycle 30/30, Tangle cancellation 16/16 and probe
  cancellation 21/21. Release workflow checks passed 11/11. Shell syntax,
  error-level ShellCheck and diff whitespace checks passed.
- The first fresh Codex review identified startup acknowledgement, shared
  pruning locks and Tangle operation mapping gaps. All three were corrected
  and covered by the focused checks above. A fresh GPT-6 Astra high review of
  the corrected patch returned `NO ACTIONABLE FINDINGS`.
- `make ci-changed` selected the full matrix and exited successfully: 16 smoke,
  325 unit and 8 integration suites passed. Focused reruns above cover the
  refinements made after the full run began. `make sync-check` passed; npm's
  package dry-run includes both PID-ledger helpers. Existing file modes are
  unchanged.
- Provider execution tests use local fixtures. No live-provider compatibility
  result, merge or new release is claimed by these checks.

## Method activation evidence

- Commands and flow skills select relevant methods through one shared block.
  Both `spawn_agent` and `run_agent_sync` include it before context budgeting.
  Task classification excludes the added method menu. Repeated enrichment
  preserves one copy of the contract.
- Independent review accepts natural language and the existing flag, respects
  preferences and billing limits, and does not authorize nested provider calls.
- Engineering prototypes route through planning; UI prototypes retain design
  routing. Explicit multi-provider commands retain their execution contracts.
- Both READMEs and generated release summaries describe end-user benefits.
  The manifest is the source of the corrected release summary. Release guidance
  keeps CI and test-maintenance details out of README What's New.
- Focused method checks passed 14/14. Synchronous transport/lifecycle checks
  passed 29/29 and background transport/lifecycle checks passed 28/28.
  The provider fixture captures the actual stdin; metadata checks capture the
  input to context budgeting rather than assuming the old prompt length.
- The required changed-file gate selected the full matrix. Smoke passed; the
  unit run completed 321/324, then all three failed suites passed targeted
  reruns: plan resolution 15/15 unchanged, MCP 5/5 after installing existing
  dependencies, and background lifecycle 28/28 after correcting its fixture.
  The initial plan-resolution failure was not reproduced on rerun.
- All 8 integration suites passed after the unit run and targeted corrections.
- Router checks passed 67/67 after removing an arbitrary Markdown line-count
  assertion. Post-review dry-run, public-reference and README synchronization
  suites passed. Plugin assembly, package inclusion, shell syntax and YAML
  parsing checks passed.
- Codex review findings about flow frontmatter placement, description generation
  and the subagent preamble were corrected. The reviewer verified the final
  description and preamble corrections with neither finding remaining actionable.
- A01-A12 are behavioral evaluation definitions, not live execution results.
  This work does not establish a measured improvement in model compliance.

## Start Here

1. Run `git status --short --branch`, inspect the latest commits, and compare
   the branch diff against `upstream/main`.
2. Read the relevant repository issue and implementation specification when
   available. Do not migrate the Beads schema if it is blocked.
3. Read `AGENTS.md`, `CLAUDE.md`, and this handoff before changing files.
4. Read the relevant `bd` issue before changing files; use the repository issue
   tracker as the task system of record.

## Implemented Scope

- Adapted architecture, debugging, TDD, planning, audit/debate,
  design-lineage, skill-authoring, work-slicing, and pressure-testing methods
  to be host-native by default. Explicit Octopus workflows remain available.
- Added `skill-prototype` and reusable architecture-simplification,
  debug-feedback-loop, and domain-modeling blocks.
- Added strict, offline routing preview with sanitized environment handling and
  no provider dispatch.
- Added resumable setup receipts, atomic legacy configuration writes, bounded
  locking, and concurrent first-writer protection.
- Extracted the OpenAI-compatible helper's bounded process-tree supervision
  into `shared/process_supervisor.py`.
- Added 38 acceptance cases and a test-consolidation benchmark while retaining
  tests that exercise distinct failure modes.
- Added Matt Pocock MIT attribution, the complete license notice, and package
  inclusion checks for adopted methods and evaluation data.
- Updated Claude, Codex, Cursor, and Factory adapters plus user and developer
  documentation.

## Review Findings Already Resolved

- Restored compatibility contracts for LSP-assisted architecture work,
  conditional intent questions, strategy rotation, hard gates, and debug
  self-regulation after the first full matrix exposed missing behavior.
- Replaced a racy setup-state lock open with a bounded existing-or-exclusive-
  create loop. A barrier-released 25-iteration concurrency regression test now
  covers simultaneous first writers.
- Hardened setup-state replacement, broken resume handling, strict value types,
  oversized state rejection, bounded JSON depth and integer handling,
  permission handling, and traceback suppression.
- Invalid initial readiness, failed provider rechecks, and failed host-local
  verification now invalidate prior completion through the same receipt
  transition instead of leaving stale success.
- Hardened routing preview deadlines, incomplete output handling, preference
  readback, and reviewer-value validation.
- Prevented FIFO blocking and preserved bounded process-tree cleanup in the
  shared supervisor.
- Rejected lone Unicode surrogates and NUL strings before setup state reaches
  shell JSON consumers. Invalid requests exit 2; invalid stored state exits 3
  without replacing or deleting existing bytes.
- Made `legacy-reset` validate stored JSON before deletion, closing the final
  GPT-6 Astra review finding. The repeated Astra high pass returned
  `NO ACTIONABLE FINDINGS`.

## Verification

- Documentation follow-up updates both READMEs, the Unreleased changelog,
  workflow examples, command/documentation indexes, and the delivery contract.
  It keeps the published v11.0.1 metadata unchanged and distinguishes local
  setup verification from a live provider task.
- The documented routing-preview request returned the expected result. All 72
  local Markdown file links in the edited documents resolve. Generated-file
  synchronization, plugin assembly, and diff checks pass.
- The documentation follow-up full run passed 16 smoke suites and 322 of 324
  unit suites. The new documented variable needed a coverage-manifest entry;
  adding its existing routing-preview test fixed that suite, which passed 9/9.
  The unchanged heartbeat timeout fallback suite passed 14/14 on an isolated
  rerun after a missing child-PID assertion failed in the matrix. Its fixed
  delay may depend on scheduling; follow-up `oco-3gu` records that unresolved
  test-stability concern. No timeout behavior or test assertion was changed.
- The remaining integration gate passed all 8 suites after the documentation
  coverage fix. Only affected suites and the remaining integration gate were
  rerun; there was no second full-matrix run.
- Before the code commit, `make ci-changed` passed its full matrix: 16 smoke suites, 324
  unit suites, and 8 integration suites.
- Focused routing preview passes 11/11, resumable setup state passes 19/19, and
  the documented first-success command paths pass 15/15, including 25
  concurrent first-writer iterations.
- Documentation synchronization passes 143/143; `make sync-check` and
  `git diff --check` pass.
- The focused selector now supports `--committed-only`, so CI-side recursive
  executable-bit setup cannot turn a mode-only helper change into a 323-suite
  fallback. The selector contract passes 25/25 checks, and the retired
  integration contract passes 9/9.
- Release PR #1019 passed the complete core matrix, symlink lane, integration,
  smoke, package, portability, and summary gates. The exact post-merge main
  run also passed full core, deep council, symlink, integration, smoke,
  package, portability, and summary gates.
- Plugin assembly validates 120 skills, 53 commands, 51 agents, and 31 agent
  configuration references.
- Claude validates both the plugin and marketplace manifests. The only warning
  is the pre-existing notice that the repository-root `CLAUDE.md` is not plugin
  context.
- Codex CLI 0.153.4 installed the candidate from an isolated local marketplace
  and repeated installation after commit. Native `skills/list` discovered 63
  packaged skills plus 20 converted commands with no errors; all 63 generated
  OpenAI descriptors disable implicit invocation.
- The npm package archive includes the notices, full third-party license,
  workflow blocks, and evaluation fixtures. Post-commit packaging from a tracked
  Git archive passed with the license, evaluation fixtures, and shared
  supervisor included.
- No executable mode changes are present, and all JSON manifests and fixtures
  parse successfully.

## Deliberate Limits

- Paid live-model behavior cases are recorded as `not_run`; no billable
  provider validation was needed for the deterministic contracts in this
  change.
- The existing macOS council PTY case remains skipped, with its deny path
  covered separately. It is not part of this implementation.
- Versioning, tagging, marketplace publication, pull-request merge, and
  release verification for v11.1.0 are complete under `RELEASING.md`.

## Workspace Safety

Keep implementation work in an isolated checkout when parallel work requires
it. Preserve user-owned dirty files, credentials, and agent state; do not
stage, overwrite, or discard them. Remove a temporary worktree only after its
branch is clean, useful changes are committed or preserved, the branch is
pushed, and no process or agent session is using it.
