# AI Agent Handoff

Last updated: 2026-09-06

Status: v11.1.0 is released from main squash commit
`bfe1f42ff3362cb2d825cfbc44a62f3e16327452`. The release includes the workflow
method and resumable setup work, proportional CI test tiers, committed-only
changed-surface selection for clean CI checkouts, and deterministic release
regression fixtures. Tag `v11.1.0`, the GitHub release, and the shared Claude
and Codex marketplace entries are published at that exact commit.

Tracking: use the repository issue tracker and checked-in implementation
documentation as the source of truth. Do not put private checkout paths,
credentials, or host-specific state in this public handoff.

Next action: use the focused selector for ordinary plugin PRs. Keep shared CI,
unknown, or safety-net changes fail-closed to the complete core matrix; main,
scheduled, manual, merge, and release paths retain deep council coverage.

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
