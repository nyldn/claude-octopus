# AI Agent Handoff

Last updated: 2026-08-21
Status: PR #949 is merged. PR #942's conflict-resolved code head `885c2e0b` is
pushed and passed exact-head Test Suite run `32519797414`; CodeRabbit requested
this handoff-state update, and the separate `pr-review` job failed because its
Copilot fallback exceeded monthly quota. The v9.66.0 release is authorized and
pending required verification, approvals, protected merges, and release
execution.
Branch: `fix/recent-pr-audit-regressions`
Current release: [v9.65.0](https://github.com/nyldn/claude-octopus/releases/tag/v9.65.0)
Tracking: Beads `oco-27j`; PRs #941, #942, #946, and merged PR #949
Next action: require fresh exact-head CI, approval, and zero unresolved threads,
and document the provider-capacity `pr-review` failure without bypassing branch
protection. Then merge verified PRs #941, #942, and #946 and release v9.66.0
from the resulting squash commits on `main`.

## Recent PR Audit Regression Fixes (`oco-0u2`)

- Source-of-truth baseline: canonical `nyldn/claude-octopus` main at
  `242e51d3`, after merged PRs #935 through #939. The live GitHub audit on
  2026-08-19 found no open GitHub issues. PRs #940 and #941 are open, approved,
  and unrelated to these code paths.
- Reproduced defects: design review silently bypassed an empty/invalid provider
  policy with Claude fallback and admitted explicit env overrides without a
  final allowlist check; provider-local role defaults overrode explicit
  `routing.roles`; a minimal incomplete Council summary left `run-status.json`
  at `running`; raw provider exits 124/137/143 were labeled as internal
  timeouts; and Tangle lowercased file paths and pipe-joined tuple fields,
  collapsing distinct blocker identities.
- Corrections: design review now propagates fleet-policy failure and validates
  every final seat against the active allowlist before dispatch; explicit
  role/phase routing precedes provider-local defaults; fallback summaries write
  a terminal `finished/incomplete` beacon; only the detached reaper's
  `internal-watchdog` provenance can produce a timed-out seat and that
  provenance is persisted in `seats[]`; Tangle identities are JSON tuples with
  case-preserved paths and normalized titles.
- TDD evidence: each reported behavior was made red before production changes.
  Focused green results are design review 6/6, model resolution 19/19, Tangle
  correction loop 16/16, AGY provider 50/50, and Council 86/87 with zero
  failures and its one documented macOS PTY skip. The AGY catalog-timeout test
  now proves the stalled provider started, did not complete, and was bounded by
  a monotonic elapsed-time window.
- Full-gate evidence: `CI=true GITHUB_ACTIONS=true make ci-changed` selected the
  full rule and ran `make ci-local`; it exited 0 with all smoke, unit,
  integration, packaging, sync, and CI-only verifications passed. Council again
  passed 86/87 cases with zero failures and its documented PTY skip.
- First GitHub review response: CodeRabbit raised four inline findings against
  protected head `f096cade`. All four were verified before editing. The real
  detached watchdog now returns a kill-style status that agrees with its
  `internal-watchdog` provenance; chair-fallback seat records include nullable
  `timeout_provenance`; the AGY catalog-timeout regression unsets inherited
  strict mode; and that test now uses a timeout-derived upper bound and proves
  the stalled process was terminated. RED reproductions covered each behavior.
  GREEN after the fixes is AGY 50/50 and Council 86/87 with zero failures and
  the documented PTY skip. A fresh `CI=true GITHUB_ACTIONS=true make
  ci-changed` again selected and passed the complete `make ci-local` matrix.
- Review evidence: the independent AGY pass returned only generic conditional
  approval, with no diff-specific finding that survived verification. The
  final Codex reviewer spent its ten-minute window reading the repository and
  rerunning focused suites, then returned empty output; Claude was blocked by
  spend limits and Copilot by monthly quota. These are recorded as degraded
  review capacity, not approvals. A local spec/code-quality pass found only a
  stale test comment (`3s` versus the actual `6s` mock sleep), which was fixed.
- Repository state: `.beads.gate.lock` remains untracked and untouched because
  it belongs to another agent. The stable plugin symlink had been left pointing
  at a deleted review worktree; it was restored to this canonical checkout and
  provider doctor checks passed with optional-provider warnings only.
- Live queue caveat: PR #941 is approved, all repository checks pass, and its
  sole review thread is resolved. PR #940 is approved by CodeRabbit and has no
  review threads, but GitHub shows no repository Test Suite run; do not merge it
  until proportional repository checks are attached and green. Its new chart
  host is a third-party workaround, not the official Star History domain, so
  verify service ownership/reliability before accepting that dependency.
- Prior protected-head evidence: review-response commit `1d21f65a` passed
  portability, macOS and Ubuntu smoke/unit tests, symlink-path tests, full
  integration, and Test Summary run `32213734617`; native `pr-review` also
  passed. CodeRabbit approved that SHA, all four verified findings received
  evidence-specific replies, and GitHub reported zero unresolved threads. That
  evidence must be refreshed now that current `main` has been merged locally.
- Current protected-head evidence: conflict-resolved commit `885c2e0b` was
  pushed and exact-head Test Suite run `32519797414` passed portability,
  macOS/Ubuntu smoke and unit tests, symlink-path tests, full integration, and
  Test Summary. The local working tree retains only the pre-existing modified
  `.beads/interactions.jsonl` and untracked `.beads.gate.lock`; both belong to
  other session state and remain untouched. CodeRabbit's only new finding was
  this missing handoff metadata. The `pr-review` job is not review evidence: its
  primary path failed and its Copilot fallback reported exhausted monthly quota.

## Persona Spawn Routing (merged PR #949)

- Incident: the shipped architecture skill invoked `orchestrate.sh spawn
  backend-architect`, but the spawn command passed that curated persona name
  directly to provider validation. The runtime rejected it as an unknown agent
  even though help and the skill documented persona-name spawning.
- Fix: `resolve_persona_spawn_target()` resolves curated persona names through
  `agents/config.yaml`, prefers an available configured primary provider, uses
  `fallback_cli` only when needed, and leaves direct provider targets on their
  existing path. The persona name is retained as the runtime role. AGY remains
  synchronous in live runs and genuinely dry in `--dry-run` mode.
- Regression evidence: the new persona suite passed 9/9; AGY provider coverage
  passes 50/50; agent predicates pass 13/13; Bash syntax, ShellCheck error-level
  analysis, and `git diff --check` pass. A fresh non-PTY `CI=true
  GITHUB_ACTIONS=true make ci-changed` selected the full `make ci-local` matrix
  and exited 0 with all smoke, unit, integration, and CI-only checks passing.
- Merge evidence: PR #949 was squash-merged to canonical `main` as
  `b80d82dfe76098032ae57ddf1488ec65329601bd` after exact-head CI passed,
  CodeRabbit approved, and all review threads were resolved. The installed
  v9.65.0 runtime still contains the defect until the fix is released and the
  documented architecture command is re-run from the installed path.

## Release Queue

- PRs #945 and #946 both claimed issue #944. PR #945 was
  closed as superseded after a credential-gated explanation; #946 is the more
  complete fail-closed implementation and its focused YAML runtime suite passes
  18/18 at head `52e0aeee`.
- PRs #941 and #946 were approved with green checks and zero unresolved review
  threads when last audited; refresh those facts against their exact heads
  before merging. #946 is the more complete fail-closed fix for issue #944.
- #940's one-line chart change serves a valid SVG and destination but GitHub
  still reports it blocked with no Actions checks.
  PR #948's code-focused test passes 13/13 and its normal Test Suite is green,
  but the required PR-review job failed because both the Claude spend limit and
  Copilot monthly quota were exhausted. Do not treat #940 or #948 as merge-ready.
- Release version: post-v9.65.0 `main` includes the additive vendor-balanced
  Council feature from PR #932, so repository SemVer policy requires v9.66.0,
  not v9.65.1. Include verified PRs #941, #942, #946, and #949; exclude #940
  and #948 unless their independent blockers are resolved.

## Release Currency Audit (post-v9.64.0)

- Open work: `gh pr list` and `gh issue list` with `--json` return empty arrays
  for both `nyldn/claude-octopus` and `nyldn/claude-octopus-dev`. Bare list
  output is not sufficient evidence on this host, because a failing RTK hook
  returns an empty result instead of an error.
- Generated surfaces: `make sync-check` exits 0 and leaves no working-tree
  drift, covering README, `PRODUCT.md`, `.claude-plugin/marketplace.json`
  counts, the openclaw index, and the generated Codex and Cursor commands.
- Changelog: `## [9.64.0]` is present and `## [Unreleased]` is empty, so no
  entry is pending. The changelog dates 9.64.0 as 2026-08-13 while the GitHub
  release published 2026-08-14; cosmetic disagreement, not corrected here.
- Tags and releases: `v9.64.0` dereferences to `a91f8067`, whose Test Suite run
  `31825411320` passed. The release is published, not a draft or prerelease.
  Local tags match `upstream` with no orphans in either direction. Main is two
  docs-only commits ahead of the tag and was correctly not retagged.
- Shared marketplace drift found and fixed: `nyldn/plugins` was last synced at
  v9.63.0 on 2026-08-12 (`8ced4726`), so the v9.64.0 sync step had been missed
  and installs from `nyldn-plugins` still resolved to 9.63.0.
  `scripts/sync-shared-marketplace.sh --check` reproduced this
  (`shared=9.63.0, local=9.64.0`, exit 1). The sync was run and pushed as
  `2910f8de`; the re-check now reports the octo entry up to date at v9.64.0 and
  the live file confirms `octo = 9.64.0`. The Codex `claude-octopus` selector is
  unversioned and was left untouched.
- Open at handoff time: main Test Suite runs `31829961517` and `31830012819`
  for the two docs-only commits were still in flight and are unverified here.
- Host defect, now fixed: `~/.claude/hooks/rtk-rewrite.sh` failed its integrity
  check, so RTK refused to run and swallowed `gh`, `grep`, `head`, and `ls`,
  returning empty output instead of an error. Root cause was version drift, not
  tampering: rtk 0.45.0 retired the shell-script hook for a native binary hook,
  and the leftover script from an older rtk no longer matched the recorded hash.
  The script was read in full and backed up before replacement.
  `rtk init -g --auto-patch` removed it and registered `rtk hook claude`;
  `rtk verify` now passes 154/154.

## Beads Tracking Restored (schema v49 to v65)

The long-standing Beads blocker recorded throughout this file is resolved. Every
older section below that says "Beads remains blocked" or "no migration was run"
is historically accurate for its own session but no longer describes current
state.

- Authority: the user confirmed this Mac is the sole clone of the `oco`
  database, which satisfies the single-designated-migrator rule. The Dolt
  remote is `origin` (`git+https://github.com/nyldn/claude-octopus-dev.git`);
  there is no second remote to fork against.
- Backup before migrating: `.beads/embeddeddolt` was archived to
  `.beads/backup/embeddeddolt-pre-v65-20260814.tar.gz` (gitignored), with
  `issues.jsonl` and `config.yaml` copies alongside it.
- Migration: `bd migrate --force` applied all 16 migrations, set
  `repo_id 3ce3d674` and `clone_id 14bbce12`, and reported Dolt version 1.2.1.
  `bd dolt push` advanced `refs/dolt/data` from `1222bc33` to `29158b82`.
- Verification: reads, writes, and push all work. `bd stats` reports 34 issues.
  A `bd remember` write succeeded, recording that this machine is the
  designated migrator.
- Housekeeping: `git config beads.role maintainer` was set to clear the
  unconfigured-role warning. Stale `oco-004` (remove dead Gemini provider) was
  closed against evidence, not assumption: `scripts/helpers/gemini-exec.sh` is
  absent and `tests/unit/test-retired-gemini-provider.sh` passes 11/11, matching
  the v9.61.3 delivery via PR #854. `refs/dolt/data` is now `f62293ab`.
- Current backlog: two open issues remain, `oco-aek` (P2, expand lifecycle event
  vocabulary) and `oco-fgg` (P3, control-plane major bets). Nothing is in
  progress or blocked.
- Going forward: use `bd` as the task system of record again, per `CLAUDE.md`.
  GitHub issues are no longer the fallback tracker.

## Claude Handoff — Paused Production State

- Production deployment is complete: GitHub release `v9.64.0` is published at
  https://github.com/nyldn/claude-octopus/releases/tag/v9.64.0.
- The release tag points to tested code commit
  `a91f80671dd530a6beed80b0bec56263b491435b`; main Test Suite run
  `31825411320` completed successfully for that exact commit.
- The later `80d071a6` commit only records this release in the handoff; it is
  pushed to `upstream/main` and must not be retagged as v9.64.0.
- Working tree is on `main`, aligned with `upstream/main`; the only untracked
  item is the preserved harness file `.beads.gate.lock`.
- No open pull requests remain. Contributor fork branches from merged PRs may
  still exist because GitHub denied upstream deletion permission.
- Safe resume: read this handoff, verify `git status --short --branch`, and wait
  for the user's next instruction before mutating code, releases, or branches.

## Production Release v9.64.0

- The exact `main` commit `a91f80671dd530a6beed80b0bec56263b491435b` passed
  the required main Test Suite run `31825411320` with conclusion `success`.
- Annotated tag `v9.64.0` points to that exact commit and was pushed to the
  canonical repository. The GitHub release is published, not a draft or
  prerelease: https://github.com/nyldn/claude-octopus/releases/tag/v9.64.0
- Release notes were generated from the existing `CHANGELOG.md` v9.64.0 entry;
  no version bump was repeated because v9.64.0 was already present in the
  manifests and changelog.

## Pull Request Queue Closure

- Merged PRs: #867 as `c8189634`, #899 as `c6558757`, #917 as `53d37c1c`,
  #918 as `ef542498`, and #877 as `318e6f4c`.
- PR #877's protected head `33ee5b1855a5a5161ab6eff6097c1f07f394ffa0`
  passed smoke, portability, Ubuntu and macOS unit, symlink-path, full
  integration, summary, and CodeRabbit checks. CodeRabbit had no unresolved
  review threads when it completed.
- GitHub reports zero open pull requests. Upstream-owned merged branches were
  deleted where controllable. GitHub denied deletion of contributor-owned
  branches for #867 (`borng`), #899 and #917 (`Jhacarreiro`), and #877
  (`Marc-oss-hub`); upstream maintainers can update these through maintainer
  access but cannot delete branches from contributor forks.
- Beads remains blocked by its pending schema migration. No migration was run,
  and the untracked `.beads.gate.lock` remains excluded.

## PR #877: OrcaRouter Provider

- Provider contract: OrcaRouter is an explicit, named, API-only integration;
  it does not auto-activate. Dispatch uses the configured allowlist and
  cheapest-first model fallback through the OpenAI-compatible gateway.
- Configuration safety: setup reads keys silently, stores them through the
  persistent-secret helper with mode `0600`, updates atomically, and does not
  leak the caller's `umask`. Stale shell configuration is parsed as literal
  assignments only; dynamic shell expressions are rejected rather than run.
- Wiring: detection, health, status, council, smoke, routing, quota reporting,
  marketplace metadata, public provider facts, and generated skill surfaces
  all share the suffixed `orcarouter*` resolver and enabled-plus-key contract.
- Review response: model execution is allowlisted, retry arithmetic is safe
  under `set -e`, provider resolution is loaded before standalone detection,
  status capture and paths are quoted, and release/documentation assertions
  are explicit. The first combined gate then exposed that dispatch emitted the
  new shell function while command validation rejected it; the validator now
  accepts only the two exact OrcaRouter function names and rejects lookalikes.
  The round-trip regression passes 6/6 and command validation passes 44/44.
  CodeRabbit's next review produced seven findings. Each was checked against
  the current code before editing: provider status and Council now share one
  explicit enabled-plus-key gate; secret persistence replaces both plain and
  `export` assignments; Sonnet 4.6 records its verified 1M context; empty API
  responses fail; interrupt cleanup runs through an isolated EXIT trap; and
  the resolver/temp-fixture tests use their documented contracts. No known
  review finding remains unaddressed in the local head.
- Focused evidence: OrcaRouter passes 22/22; release sync 8/8; provider registry
  contracts 14/14; shipped model resolution 7/7; shared marketplace 17/17; AGY
  50/50; availability 15/15; provider contract audit 4/4; auth validity 18/18;
  and council model selection 10/10. `make sync-check`, ShellCheck error-level
  analysis, and `git diff --check` pass.
- Final-gate evidence: after reproducing and fixing the dispatch-validator gap,
  a fresh `make ci-local` passed 16/16 smoke suites, 273/273 unit suites, and
  7/7 integration suites plus all CI-only verifications. Council passed 73/74
  cases with its one documented macOS PTY skip.
- Delivery: PR #877 was squash-merged from protected head
  `33ee5b1855a5a5161ab6eff6097c1f07f394ffa0` as `318e6f4c`. The contributor's
  fork branch remains because GitHub rejected its deletion with permission
  denied.
- Tracking blocker: Beads remains blocked by its pending schema migration. No
  migration was run.

## Issue #916: Fail-Closed Outbound GitHub Text

- Incident root cause: an agent placed generated Markdown inside a double-quoted
  shell argument to `gh api -f body=...`. Markdown backticks executed command
  substitution before GitHub CLI started, inserting the process environment
  into a public review reply. The comment was deleted after roughly eleven
  seconds. This was an agent-side GitHub write, not a Claude Octopus provider,
  AGY, or runtime credential leak. The owner revoked the Perplexity credential.
- Outbound gate: `scripts/safe-gh-comment.sh` accepts GitHub text only through a
  private file or bounded standard-input snapshot. It validates UTF-8, control
  bytes, size, repository/identifier/path arguments, common credential formats,
  sensitive assignments and structured fields, authenticated URLs, environment
  dumps, and placeholders before invoking a silent GitHub write. Scanner errors
  fail closed, and signal handling cancels the child write and removes snapshots.
- Integration: review comments/replies, inline findings, release PR creation,
  delivery, staged-review, code-review, finish-branch, and intake guidance all
  use the gate. Repository-wide agent instructions prohibit generated GitHub
  text in inline shell body arguments. Generated Codex skills were rebuilt from
  canonical `.claude/skills/` sources.
- Review response: two external review rounds were run with publishing disabled
  and Perplexity removed from the provider environment. Valid parser and signal
  findings were reproduced before fixes; the claimed PID-assignment signal gap
  was rejected twice by a deterministic trap regression. Claude and Codex
  participated; AGY reported exhausted quota, so the fail-closed local fallback
  preserved review findings.
- Security evidence: the regression suite failed on uncovered authorization,
  structured-field, prefixed-name, placeholder, equality, and quoted-option
  cases before the corresponding changes. The expanded suite now passes 64/64,
  including hard-bounded standard input and pipefail-safe credential matching. Review
  aggregation passes 27/27, review-run 31/31, PR workflow 16/16, and staged
  review 9/9. ShellCheck, `make sync-check`, and `git diff --check` pass.
- Remote portability response: PR #918's first symlink-path job exposed that the
  new test used `rg`, which is not installed on that Linux image. Production
  code was unaffected. Static searches now use portable grep plus a Python
  multiline helper; the 59/59 suite passes through a real symlink with PATH
  restricted to `/usr/bin:/bin`.
- Full-gate evidence: the final pre-handoff `make ci-local` exited zero with
  16/16 smoke, 270/270 unit, and 7/7 integration suites plus CI-only
  verifications. Two unit failures in an earlier run were traced to inherited
  `OCTOPUS_COST_MODE=premium`; both suites now clear host state and pass.
- Final review response: CodeRabbit's four current findings were reproduced
  against the rebased branch before changes. Credential matching now uses the
  required counting grep form; all skill callers treat a nonzero write as an
  unknown remote state and query GitHub before retry; finish-branch requires
  completed PR title/body values; and the bounded snapshot test is positive and
  behavioral. Focused coverage passes 63/63, the macOS provider-banner suite
  passes 10/10, and the final `make ci-local` exits zero with all required
  smoke, unit, integration, and CI-only checks.
- Final test-review response: CodeRabbit's three later findings were verified
  against the test implementation. Both cancellation tests now require their
  child-readiness marker before TERM can pass, the launch-gap test observes for
  two seconds against a 250 ms mock delay, and detector/skill failures report
  their independent values. The focused security suite passes 64/64. The fresh
  full local gate for this exact test-only head passed 16/16 smoke, 270/270
  unit, and 7/7 integration suites plus CI-only verifications.
- AGY test isolation: a later full run exposed that the stalled-version
  regression timed the entire live doctor while inheriting every installed host
  provider CLI. Production AGY timeout code was unchanged; the test now limits
  PATH to its mock AGY and system tools. It passed three consecutive focused
  runs, then the final full gate passed the complete AGY suite 50/50.
- QA throughput: the council environment-isolation regression no longer copies
  this checkout's multi-gigabyte ignored directories. It runs from a tiny source
  fixture and takes 5 seconds in isolation without changing production
  behavior. In the full sequence it still incurred a separate 260-second,
  state-dependent council timeout, so that remaining latency is not represented
  as fixed.
- Tracking blocker: Beads remains blocked by its pending schema migration. No
  migration was run, and the untracked `.beads.gate.lock` remains excluded.

## Issues #900 and #902: Tangle Lifecycle Ownership

- Root causes: the top-level `EXIT INT TERM` cleanup trap removed a temporary
  directory but swallowed signals without exiting or reaping providers; Tangle
  had no active-work cancellation registry; tree-only cleanup could lose a
  child after its shell leader exited; and the completion watcher treated a
  living but childless wrapper as active forever.
- Process ownership: legacy workers enter dedicated process groups, so the
  recorded worker PID is also its PGID. Cancellation first kills that group
  atomically, with a portable frozen descendant walk for legacy callers and
  macOS/minimal environments without `pgrep`.
- Lifecycle ownership: Tangle registers task identity before spawn, reconciles
  the PID ledger to close the post-spawn handoff race, marks cancelled outputs
  and completion records, prunes runtime metadata, restores caller traps, and
  handles both explicit signals and unexpected `set -e` exits.
- Provider liveness: `spawn_agent_capture_pid` returns the provider root, not a
  wrapper, so a living PID with no descendants remains active until it writes
  its completion marker. The explicit `OCTOPUS_TANGLE_DEADLINE` remains the
  operator-controlled bound; dead providers enter missing-marker recovery.
  Non-TTY progress is emitted only when its count changes.
- Run isolation: default Tangle IDs now use an atomic reservation instead of
  `date +%s` plus `$$`, preventing same-second worktree and branch collisions
  exposed when the old final two-second sleep was removed. Explicit run-ID
  overrides now reject traversal, and zero-byte reservations older than seven
  days are pruned once daily without weakening same-day atomic uniqueness.
- Review hardening: Tangle refuses provider dispatch when either cancellation
  helper is unavailable, never signals the orchestrator PID/group, snapshots reachable legacy
  descendants before STOP, uses portable `ps -A`, serializes PID-ledger pruning
  with spawn appends, stops before pruning when `flock` acquisition fails, and
  ignores dead targeted PIDs. Status checks are SIGPIPE-safe and the integration
  assertion reads whole Tangle functions. The spawn PID suite again uses the
  shared test framework's temp-directory cleanup instead of replacing its trap.
- Linux CI regression: the whole-function assertions still piped a large shell
  variable through `grep -q`. On Linux, the early reader exit closed the pipe,
  `echo` received SIGPIPE, and `set -o pipefail` failed the integration job.
  Here-strings with non-early-closing `grep -c` preserve the semantic assertions
  without a producer-side broken pipe; the focused suite passes 19/19.
- TDD evidence: lifecycle cancellation passes 16/16, missing-marker recovery
  4/4, run-worktree isolation 16/16, Markdown plan/run-ID resolution 15/15,
  contextual review wiring 54/54, spawn PID capture 10/10, and the
  value-proposition integration test passes 19/19.
- Historical #900/#902 branch-gate evidence: the final non-interactive
  `make ci-local` before stacking #901 passed 16/16 smoke suites, 268/268 unit
  suites, 7/7 integration suites,
  and the CI-only verifications. The earlier 267/268 run exposed only a brittle
  five-line static heartbeat assertion; production ordering was correct, and
  the replacement semantic-order assertion passes in the final sweep. A prior
  PTY run was invalid for the stdin-isolation fixture because its deliberate
  `cat` read waited on terminal input.
- Tracking blocker: Beads is still unreadable on schema v49 because its reserved
  v65 migration has not been applied. No migration was run; GitHub issues are
  the temporary tracker.

## Issue #908: Canonical Review Findings

- Root cause: several consumers ran `jq '.findings | length'` directly on an
  artifact that could contain more than one top-level JSON document. `jq`
  emitted one scalar per document (`0\\n0` or `1\\n1`), breaking Bash arithmetic
  and rendering the same finding once per document.
- Trust boundary: verifier and synthesis output must normalize to exactly one
  object containing a findings array. Invalid and multi-document output falls
  back locally before the final artifact is written.
- Consumers: debate, synthesis events, proof packets, terminal reports, PR
  summaries, and inline comments now use a scalar count helper that either
  returns one non-negative integer or fails with no output.
- Deduplication: exact duplicates use file, line, category, and title/message as
  identity. Stable first-occurrence reduction preserves the synthesizer's
  severity/rank ordering.
- Rendering: invalid artifacts fail closed without findings, arithmetic errors,
  or duplicate output. The missing-repository inline-comment fallback renders
  once.
- TDD evidence: aggregation coverage failed on the missing normalizer, scalar
  count, multi-document renderer, rank preservation, non-object entry, and
  equal-severity order cases. It now passes 27/27; review-run passes 31/31 and
  PR-review workflow passes 16/16.
- Full-gate evidence: the final `make ci-local` after the non-object and stable
  order review changes passed 16/16 smoke, 267/267 unit, and 7/7 integration
  suites, plus all CI-only verifications.
- Throughput follow-up: [issue #910](https://github.com/nyldn/claude-octopus/issues/910)
  proposes a fail-closed changed-files local gate while retaining the full CI
  and release matrix.

## Issue #910: Fail-Closed Changed-Scope Local Gate

- Current state: [PR #913](https://github.com/nyldn/claude-octopus/pull/913)
  was squash-merged as `25a2e80c`; issue #910 is closed. The `make ci-changed`
  baseline is now on `upstream/main` and selected the full matrix for PR #912.
- Root cause: repository instructions required all unit and integration suites
  before every code push. The complete unit sweep reached 267-268 suites, and
  the unrelated Council suite alone took 188-218 seconds during recent focused
  fixes.
- Selector contract: `tests/changed-scope.tsv` maps known changed-path globs to
  required suite globs. The selector includes committed branch changes plus
  staged, unstaged, and untracked paths, prints the changed files, matching
  rules, and selected suites, and accepts deterministic explicit paths for
  regression testing.
- Fail-closed boundary: shared orchestration, workflow, spawn, dispatch,
  generators, plugin manifests, CI, the Makefile, the test runner, the selector
  and manifest themselves, and every unmapped path select `make ci-local`.
  Missing comparison bases, missing mapped suites, and malformed empty mapping
  policies also select the full matrix. Known user-owned harness artifacts such
  as `.beads.gate.lock` and `.octo-continue.md` are explicitly ignored.
- Focused boundary: every focused run still executes `make sync-check`, all 16
  smoke suites (including syntax and packaging), and the suite-reachability
  guard. Explicit test-runner suite paths are confined to existing
  `test-*.sh` or `validate-*.sh` files under `tests/`.
- CI and release: GitHub Actions continues to run the authoritative complete
  unit and integration jobs. `make ci-local` remains mandatory before merge and
  release; agent instructions now distinguish iterative, ordinary-push, and
  final gates.
- TDD evidence: the first regression passed only 1/10 cases before the command,
  manifest, and explicit-suite support existed. It now passes 17/17, including
  deterministic review/model plans and full-matrix fallback for shared,
  generator, unknown, selector, manifest, and missing-base changes. Automatic
  base discovery never narrows to `HEAD~1`, which could omit earlier commits.
- Runtime evidence: a model-resolver-only plan selected seven model/provider
  suites plus suite reachability, excluded Council, and passed all 16 smoke
  suites and all 8 selected suites in roughly one minute. The current #910
  branch selects the full matrix because it changes the selector, manifest,
  Makefile, and test runner.
- Final-gate evidence: `make ci-local` passes 16/16 smoke suites, 268/268 unit
  suites, 7/7 integration suites, and the CI-only verifications.
- Review evidence: the implementation matches the requested proportional
  edit/push/final contract. Code-quality review found one unsafe automatic
  `HEAD~1` comparison fallback that could omit earlier branch commits; it was
  removed, covered by the 17/17 selector regression suite, and no blocking
  review finding remains.
- Tracking blocker: Beads remains unreadable on schema v49 because its reserved
  v65 migration has not been applied. No migration was run; GitHub issue #910
  is the temporary tracker.

### Full-gate optimization follow-up

- Root cause measurement: a fresh standalone Council baseline passed but took
  220.65 seconds. Repeated fixture scenarios each paid detached-seat polling
  and several test cases rebuilt byte-for-byte-equivalent dry-run, standard,
  chair-fallback, or all-approve artifacts for separate assertions.
- Optimization boundary: production Council seats remain detached. Internal
  fixture dispatch uses the existing inline path, while the dedicated atomic
  rename, signal survival, timeout, descendant cancellation, exit propagation,
  and escape-hatch tests still exercise the real detached transport. Identical
  fixture artifacts are cached only within the Council suite; every assertion
  and unique failure scenario remains.
- Test isolation: `tests/helpers/test-framework.sh` now defaults
  `OCTOPUS_TANGLE_RUN_WORKTREE=false` while preserving an explicit caller
  setting. `test-tangle-run-worktree.sh` explicitly unsets the flag and still
  proves production-default isolation. Eleven Tangle suites passed without
  changing repository worktree or `octopus/run/*` ref counts.
- Profiling: `tests/run-all-tests.sh` records wall time around every suite and
  prints a deterministic top-ten `Slowest suites` table. The fresh full unit
  run identified Council (166s), knowledge routing (38s), lifecycle events
  (24s), Octopus events (23s), and provider auth validity (22s) as the leading
  remaining costs.
- Performance evidence: the standalone Council suite fell from 220.65s to
  150.35s, a 31.9% reduction, while passing 73/74 cases with the same one known
  macOS PTY skip. No suite or assertion was deleted.
- TDD/review evidence: the new harness/timing regressions failed 2 cases before
  implementation and pass 19/19 after it. The fixture parent-context
  reproduction failed before the inline path and passed afterward. An AGY
  adversarial test review led to coverage for inherited `true`, failing fixture
  dispatch, and stale sentinel cleanup. Spec review rejected sharing the
  standard-depth benchmark fixture with a quick-depth run before delivery.
- Final verification: fresh `make ci-local` completed in 695.40s and passed
  smoke 16/16, unit 268/268, integration 7/7, and the CI-only verifications.
  Repository state remained exactly 15 worktrees and 1,251 `octopus/run/*`
  refs before and after the complete gate; the prior full run had left 94 stale
  worktree registrations. Source commit `9d9e6bed` is pushed to origin and
  upstream.
- Commit-bound remote verification: GitHub Test Suite run `31738318645` passed
  portability, both smoke platforms, the symlinked-path run, both full unit
  platforms, and full integration for head `4136fa87`; CodeRabbit approved that
  head without inline findings. Later handoff-only commits require their own
  matching-head checks and review before merge. The separate `pr-review` job is
  red because Claude hit its weekly limit and the Copilot fallback hit its
  monthly quota; it reported no code finding.

## Issue #904: AGY Catalog IDs and Preflight

- Root cause: current `agy models` emits `model-id<TAB>display label`, but
  `validate_agy_model_name` compared a requested pin against the entire row.
  Both `gemini-3.1-pro-high` and `Gemini 3.1 Pro (High)` were therefore rejected
  even while the error output displayed them.
- Catalog contract: exact model IDs and exact display labels are accepted;
  partial matches remain rejected. Legacy one-label-per-line output remains
  compatible. The live lookup has a five-second default total cap through the
  repository's portable process-group timeout, configurable within the same
  one-to-thirty-second bound as other startup probes.
- Preflight contract: the effective AGY pin comes from `OCTOPUS_AGY_MODEL`, then
  `providers.agy.default`, then `default`. An absent catalog entry reports
  `AGY_STATUS=model-invalid`, excludes AGY from available providers, and prints
  a corrective `agy models`/`default` instruction.
- Provider boundary: retired direct Gemini execution remains disabled. AGY is
  the supported Antigravity CLI seat even when that service exposes Gemini
  models.
- Evidence: the real installed catalog reproduces the tab-separated shape; both
  the live ID and label now validate. The AGY provider suite passes 50/50,
  including a red-to-green one-second stalled catalog test and behavioral
  `cmd_detect_providers` output/cache checks for valid and invalid models. The
  AGY research defaults, resolver, council selection, and provider-detection
  suites pass. `make sync` and `make sync-check` are clean. The final
  non-interactive `make ci-local` after review hardening passed 16/16 smoke
  suites, 267/267 unit suites, 7/7 integration suites, and the CI-only
  verifications. After rebasing onto PR #913, `make ci-changed` correctly failed
  closed to the full matrix and passed 16/16 smoke suites, 268/268 unit suites,
  7/7 integration suites, and the CI-only verifications.
- Tracking blocker: Beads remains unreadable on schema v49 because its reserved
  v65 migration has not been applied. No migration was run; GitHub issue #904
  is the temporary tracker.

## Issue #915: Review-Sized AGY Dispatch and Live Health

- Root cause: `scripts/helpers/agy-exec.sh` deleted every whitespace match with
  Bash global parameter substitution to determine whether a prompt was empty.
  On macOS Bash 3.2 this became superlinear for review-sized mixed-content
  prompts and consumed CPU for minutes before `agy` was ever launched. The same
  pattern also guarded silent-output retry.
- Dispatch fix: both checks now use Bash 3.2-compatible regular-expression
  presence tests for a non-whitespace byte. A 64 KiB review-like prompt begins
  dispatch within the two-second regression bound and arrives byte-for-byte at
  the fake CLI; the old code failed that test before the child launched.
- Live diagnostics: `octopus doctor providers --live` is explicit and bounded
  to 30 seconds by default. It checks the installed version, live `agy models`
  catalog/keyring access, exact configured model resolution, and a real
  print-mode response. Normal startup/preflight remains non-billable and never
  launches this probe.
- Review-response hardening: `agy --version` now uses the same portable bounded
  process-group probe before live checks, a failed live catalog/keyring check can
  no longer coexist with a passing AGY auth result, and environment assignments
  are quoted as complete `env` arguments. The new tests failed 2/50 before these
  changes and pass 50/50 after them; the stalled five-second version fixture is
  terminated and the complete doctor case finishes in two seconds.
- Authentication contract: AGY v1.1.12 has no separate login shell subcommand.
  Launch plain `agy` and complete its browser sign-in. On macOS keyring errors,
  use Keychain Access, find the Antigravity CLI item, and allow `agy` under
  Access Control. Every stale user-facing instruction was corrected and a
  repository-wide regression prevents that nonexistent command from returning.
- Live evidence: AGY CLI v1.1.12 passed all
  four doctor stages with `gemini-3.1-pro-high`. The repaired adapter then ran a
  full three-round AGY-only review of PR #913; its three findings were checked
  against the code and rejected as false positives rather than applied blindly.
- Verification: AGY provider coverage passes 50/50. `make sync-check` passes.
  On the post-#913 rebased head, `make ci-changed` selected the full matrix and
  passed 16/16 smoke suites, 268/268 unit suites, 7/7 integration suites, and
  the CI-only verifications. The real `doctor providers --live --json` probe
  then passed CLI install/version, catalog/keyring auth, exact model resolution,
  and substantive print dispatch for `gemini-3.1-pro-high`.
- Final review-response verification: `make ci-changed` again selected the full
  matrix and exited 0 after all smoke, unit, integration, and CI-only checks; the
  expanded AGY suite passed 50/50 within it. A matching real live probe then
  passed CLI v1.1.12, catalog/keyring authentication, exact resolution of
  `gemini-3.1-pro-high`, and substantive dispatch on the final implementation.
- Matching-head review: the three-round AGY-only review completed for
  `e68a848c` and returned two findings. Direct sourcing proved doctor timeout
  helpers are loaded, and production `detect-providers` returned `model-invalid`
  for a fake pin and `ok` for the real configured pin, so neither finding was
  applied. CodeRabbit's later feedback was independently checked: the two live
  doctor defects and coverage gaps above were fixed, while its raw-`echo` style
  claim was rejected because the cited lines are inside established formatted
  UI blocks that intentionally use the same output convention throughout.
- Tracking blocker: Beads remains unreadable on schema v49 because its reserved
  v65 migration has not been applied. No migration was run; GitHub issue #915
  is the temporary tracker.

## Issues #901, #903, and #905: Tangle Integrity Boundaries

- **#901:** Tangle subtask prompts now forbid applying, pushing, repairing, or
  marking migrations against persistent local, linked, remote, or shared
  databases by default. An explicit apply override retains the invariant that
  applied versions must match disk. Validation detects changed
  `supabase/migrations/*.sql` from the actual worktree diff, runs the read-only
  `supabase migration list --local` comparison, and fails closed on drift,
  unavailable history, or an empty/non-comparable result. A separate explicit
  risk override is required when local history cannot be queried.
- **#903:** Output returned from a disposable consultative workspace is wrapped
  as unverified, advisory, and non-deliverable before it reaches callers.
  Design-review synthesis is explicitly forbidden from repeating claimed file
  changes, test counts, live probes, or completed implementation as facts, and
  the operator-facing summary is labeled planning-only.
- **#905:** A clean source checkout may now contain an explicitly referenced,
  repo-contained untracked `PLAN.md`, `SPEC.md`, or `BRIEF.md` context file.
  Its contents are injected into the isolated run while unrelated untracked
  paths, modified tracked inputs, and symlinked context remain blocking. Users
  no longer need to disable either clean-baseline enforcement or run-worktree
  isolation for this common workflow. Exactly one untracked context file is
  supported per run; additional untracked inputs remain blocking.
- TDD evidence: the migration-drift helper and validation regression initially
  failed, the consultative provenance regression failed before output wrapping,
  and the untracked-context regressions failed before the baseline allowlist and
  pre-worktree resolution. A later spec review added a failing regression proving
  migration validation incorrectly depended on prompt classification; the gate
  now derives migration changes independently from the actual diff.
- Final verification: the combined review-response regression set passes,
  including 15/15 migration/worktree evidence, 16/16 run-worktree isolation,
  15/15 Markdown context resolution, 11/11 clean baseline, 9/9 ceremonies,
  8/8 subtask context, 8/8 consultative dispatch, 16/16 cancellation cleanup,
  4/4 live-provider/missing-marker recovery, 27/27 review aggregation, and
  19/19 value-proposition integration. The prior branch head also passed
  Council compatibility at 72 passed with one known macOS PTY skip. A fresh
  historical branch-only `make ci-local` at `b2ac6790` exited 0 with 16/16
  smoke suites, 267/267 unit suites, and 7/7 integration suites. Subsequent
  stacked commits brought the combined branch to 269 unit suites. On final PR
  head `b9dfba4c`, `make ci-local` passed 16/16 smoke, 269/269 unit, 7/7
  integration, and all CI-only checks. GitHub run `31752805182` passed
  portability, both smoke platforms, both full unit platforms, symlinked-path,
  full integration, and summary checks. The first complete sweep exposed three newly
  documented env vars missing from the accountability manifest; a later sweep
  exposed a stale integration assertion that inspected only 80 lines after the
  Tangle wrapper. Both contracts now map to behavioral tests, and the final
  top-level gate passed without changes to the tested production tree.
- Tracking blocker: Beads remains unreadable on schema v49 because the `leases`
  table requires the reserved v65 migration. No migration was run. These GitHub
  issues are the temporary tracker and this handoff records the blocked `bd`
  state.
- Merge state: PR #914 was squash-merged as `6e84959d`; its tree exactly matches
  tested head `b9dfba4c`. GitHub automatically closed #901, #903, and #905, and
  a post-merge open-issue query returned an empty list. Canonical `main` is
  fast-forwarded to `upstream/main`.

## Issue #898: Explicit Activation and Hook Latency

- Root cause: every prompt ran two classifiers plus a GitHub queue watcher;
  common phrases defaulted to workflow invocation; every tool call could spawn
  provider, quality, guard, and PostToolUse hooks; SessionStart injected router,
  memory, update, and setup instructions into model context; and all shipped
  skills remained eligible for model invocation. A valid
  `~/.claude-octopus/session.json` from another Claude session could also keep
  enforcement alive.
- Native activation boundary: every canonical command, source skill, generated
  Codex skill, and generated Cursor command carries
  `disable-model-invocation: true`. Explicit commands compose reusable method by
  loading the canonical skill source rather than asking the model to invoke a
  disabled skill. Claude and Copilot agent descriptions require an explicitly
  started Octopus workflow.
- Hook boundary: plain-language routing defaults to `off`; done-criteria,
  session memory, context reinforcement, GitHub work-queue checks, remote
  autonomy, output compression, strategy rotation, and statusline context are
  opt-in or tied to the active matching host session. First-run, version, and
  update notices use passive `systemMessage` output and never instruct the
  model to act. Statusline repair only repairs an existing Octopus statusline.
- Speed: current Claude Code uses handler-level permission-rule `if` filters so
  provider validation and quality checks do not spawn outside
  `orchestrate.sh`, while direct-provider guards spawn only for Codex, Qwen, or
  retired Gemini commands. Stale clients that predate conditional hooks retain
  in-process fast exits. The PostToolUse matcher no longer includes Read,
  WebFetch, or Grep.
- Stale-version recovery: `scripts/helpers/ensure-plugin-root.sh` compares the
  physical stable entrypoint with `CLAUDE_PLUGIN_ROOT` on SessionStart. It now
  replaces a valid old symlink when the host loaded a newer cache, closing the
  gap where an update succeeded but `/octo:*` continued to execute old hooks.
  Host-owned auto-update remains opt-in and startup hooks remain local-only and
  non-mutating.
- Official platform verification: Anthropic documents
  `disable-model-invocation: true` as the manual-only skill control; custom
  agents have no equivalent flag and are selected from their descriptions;
  UserPromptSubmit cannot be matcher-filtered; and handler-level `if` avoids
  process spawn for tool events on Claude Code v2.1.85 and newer.
- TDD evidence: the new activation regression began with 9 of 12 cases failing.
  It now passes 18/18, stable-entrypoint coverage passes 2/2, plugin assembly
  validates every manual gate, and affected legacy suites have been updated to
  assert the native contract rather than the removed advisory behavior.
- Performance evidence: before the fix, inactive user-prompt and done-criteria
  hooks averaged roughly 38-41 ms each, PostToolUse averaged 39 ms, and one
  unrelated provider-validator path blocked for about 18 seconds per call.
  After the fix, defense-in-depth inactive paths measured roughly 6-14 ms each;
  supported Claude Code versions skip the filtered process spawn entirely.
- Verification: `make sync`, `git diff --check`, `make sync-check`, and a fresh
  `make ci-local` all pass. The final complete run passed every smoke, unit,
  integration, and CI-only verification group. The first complete sweep exposed
  five stale tests whose old contracts required auto-invocation plus one
  pre-existing one-second macOS process-fixture race; the contracts now assert
  explicit activation, and the unchanged process-tree behavior has a reliable
  three-second fixture setup window.
- Tracking blocker: Beads remains unreadable on schema v49 because the `leases`
  table requires the reserved v65 migration. No migration was run. GitHub issue
  #898 is the temporary tracker and this handoff records the blocked `bd` state.

## Start Here

This file is the portable resume point for Claude Code, Codex, Copilot,
OpenCode, and other harnesses. It is a context packet, not the task tracker.

Read in order:

1. `RTK.md`
2. `CLAUDE.md`
3. `AI_AGENT_HANDOFF.md`
4. `git status --short --branch`
5. the latest commits and live PR state
6. the relevant `bd` issue; if Beads is still blocked, read `Tracking Blocker`
   below and do not migrate the database
7. `docs/MODEL-ROUTING-STRATEGY.md` for model-routing work
8. `docs/GPT-5.6-PROMPTING.md` for GPT-5.6 prompt changes

Harness-local files such as `.octo-continue.md` may be stale. The existing
untracked copy predates this work and remains user-owned; do not overwrite it.

## Delivered Goal

Opus 5 remains the default complex-work owner while Fable 5 stays an explicit
capability escalation, GPT-5.6 Sol remains the independent Codex peer, cheaper
tiers remain available, and explicit user pins and role/phase routes continue
to override defaults.

## Durable Decisions

- Opus 5 is the default premium Claude owner, not the only workflow model.
- Fable 5 is an explicit escalation and does not create a second Claude
  provider organization.
- GPT-5.6 Sol is the default Codex peer; Terra and Luna are standard and budget
  tiers. Sonnet 5 is the standard Claude seat.
- Claude allowlists are a compliance boundary. Normal, fast, rerouted, and
  fallback dispatches validate the final model before command serialization.
- Tangle implementation isolation defaults on. One run ID spans its branch,
  delegated tasks, markers, and validation artifacts.
- Verification-only results fail closed unless evidence types and baseline,
  reproduction, and implementation flags are internally consistent.
- Multi-model fan-out is mandatory only where the command contract explicitly
  requires council, debate, parallel, or multi-provider research.
- Runtime evidence and tests remain mandatory; duplicated prompt-only
  self-verification is removed.
- Public release/model/component/provider facts and test counts are generated
  from repository sources. `make sync` repairs drift and `make sync-check`
  rejects it.
- Review findings are verified against the current head before being marked
  resolved.

## Tracking Blocker

Beads command help is readable, but issue queries are blocked. The remote-backed
database is on schema v49 with 16 pending migrations to v65, and the current
query fails because the `leases` table is missing. Repository rules reserve
migration for the designated migrator. No migration was run, so this work could
not be claimed or recorded in `bd`; use this handoff for the blocked tracking
record.

## Resolved Issues #885, #886, and #888 through #894

- **#885:** Cost-tier definitions already existed, but `/octo:model-config`
  only printed a shell `export` instruction. A slash-command subprocess cannot
  mutate its parent shell, the resolver ignored the configurable standard tier,
  and its cache key omitted cost mode. The fix persists `cost_mode` beside the
  existing tier maps, keeps `OCTOPUS_COST_MODE` as the highest-priority override,
  applies all three tiers, and includes mode in cache identity.
- **#886:** `scripts/build-factory-skills.sh` erased the hand-maintained Cursor
  Doctor adapter and did not emit every canonical command. The generator now
  builds Doctor from the canonical Doctor skill, generates the full command
  surface, and has a non-mutating `--check` path wired into `make sync-check`.
- **#888:** The first-party PR review checked a clean Actions index with
  `target=staged`, then `tee` masked the review command's non-zero exit. It now
  materializes `origin/<base>...HEAD`, reviews that diff artifact, fails closed,
  and posts diagnostics even on failure.
- **#889:** The same workflow still installed and credentialed the retired
  direct Gemini CLI. The retired-provider boundary now scans workflow files,
  and first-party automation no longer installs or credentials Gemini.
- **#890:** Issue-comment orchestration used the same false-green `tee` pattern.
  It now preserves the Octopus exit while still posting captured diagnostics.
- **#891:** The repaired review exposed a second first-party automation defect:
  the repository had a `CLAUDE_CODE_OAUTH_TOKEN`, but the workflow installed
  unauthenticated Codex and ignored that credential. Official Anthropic CLI
  research was run through Octopus before implementation. The jobs now use
  Node 22, install Claude Code, bind the OAuth token, and set
  `OCTOPUS_DISABLE_BARE=1`; the provider report no longer initializes Claude
  to healthy without a successful Claude execution. A failed review now uploads
  its provider results and proof packet for seven days instead of discarding the
  only evidence that distinguishes auth, model, and invocation failures.
- **#892:** An orchestrated research run produced complete provider raw output
  while rich progress stayed at 0/7. Provider stdout flowed through `tee`; a
  provider hook or descendant retained that pipe, so the worker waited for EOF
  until the global watchdog. Provider prompts and output now use private,
  atomically randomized file-backed descriptors, the quota watcher observes the
  raw file, and the prompt file is removed after dispatch.
- **#893:** The corrected remote PR review proved installation and OAuth were
  healthy but all four Claude review phases failed with `You've hit your weekly
  limit · resets Aug 15, 7am (UTC)` in Actions run `31613318006`. The workflow
  first retried through GitHub Models, but Actions run `31615705396` returned
  HTTP 410 because GitHub fully retired that inference service on 2026-07-30.
  The supported replacement keeps Claude primary and retries through GitHub
  Copilot CLI using `copilot-requests: write` and the job-scoped token. Copilot
  CLI is pinned to `1.0.79`; its built-in MCP server is disabled, its available
  tool set is empty, and shell, read, write, URL, and memory permissions are
  explicitly denied. If both paths fail, the check stays red and the combined
  output plus hidden proof artifacts remain available. Provider reports surface
  the last actionable stdout or stderr error instead of replacing quota, auth,
  policy, retirement, and service failures with a generic message.
- **#894:** A real Claude lifecycle probe reproduced persistent SessionEnd
  failures from malformed `~/.claude-octopus/session.json`: both hooks ran
  unguarded `jq` substitutions under `set -e`, so one stale extra brace made
  every session end with exit 5. The same audit found three more registered
  state-reading hooks with the failure mode and multiple writers sharing the
  predictable `session.json.tmp` path. Seven lifecycle hooks now fail open on
  malformed optional state, session and compaction snapshots publish through
  atomic renames, and all shared-session updates use unique temporary paths.
  TaskCompleted also treats an uninitialized zero-task ledger as no work instead
  of incrementing it and dividing by zero. Regression coverage proves malformed
  state is silent, valid workflow verification still fires, and fixed temporary
  paths cannot return.
- Regression-first evidence: cost-mode coverage failed 7/9 before the initial
  implementation, moved to 12/12 with the first fix, and now passes 13/13 with
  the reset-failure path covered. Factory regeneration reproduced the
  missing Doctor adapter. The provider-report suite failed 0/2 before #891;
  workflow auth coverage failed 6/9 before #891; diagnostic retention failed
  9/10 before the remote failure exposed the evidence gap; output-capture
  coverage failed 1/2 before #892 and was extended after review to verify the
  prompt file is mode 600. The quota fallback began with PR workflow coverage
  at 9/13, compatible-agent coverage at 19/21, and a missing provider-report
  helper; the debate phase also failed a deliberate single-provider escape
  regression before it was routed through the override. All focused suites are
  now green: Factory 5/5, PR workflow 16/16, provider report 8/8,
  compatible-agent 21/21, agent command validation 42/42, output capture 4/4,
  cost mode 13/13, current provider defaults 11/11,
  descriptor performance 35/35,
  stable-link Doctor 6/6, Windows Doctor 5/5, retired Gemini 11/11,
  environment accountability 9/9, probe single 32/32, spawn PID 9/9,
  cancellation 21/21, AGY parallel 8/8, review
  aggregation 19/19, and handoff 13/13.
- Verification state: source commit `ea34b64f` passes `make sync-check`, all
  focused suites listed above, and a fresh
  `make ci-local`: 16/16 smoke suites, 265/265 unit suites, and 7/7 integration
  suites. The new session-state regression passes 13/13. The
  first sweep exposed three stale white-box tests that required
  `run_with_timeout` to appear directly in `spawn.sh`; each failed before its
  contract was updated to verify the shared capture helper and passed in the
  final complete run. The pre-fallback pushed head `09fed83b` passed its normal
  GitHub Test Suite; its PR review failure supplied the exact quota evidence
  that #893 now covers. Actions run `31618867031` then exercised the corrected
  fallback on commit `cb8e0c3b`: Claude reached its weekly quota, Copilot CLI
  completed every review phase, the finalizer passed, and the combined review
  artifact and PR comment were published.
- Delivery state: implementation commit `f7dd6c52` contains the review,
  authentication, portable-command, provider-reset, and descriptor-safe capture
  fixes. Commit `fc3829ef` records the retired GitHub Models attempt; source
  commit `434f6c05` replaces it with the no-tools Copilot CLI fallback, resolves
  the first review findings, pins workflow dependencies, and adds actionable
  stdout/stderr failure diagnostics. Source commit `095eefb4` closes the live
  review's remaining validation gaps: Cursor Doctor tools survive regeneration,
  empty Doctor scans remain safe under `pipefail`, the known actionlint permission
  lag is ignored only for the affected workflow, and reset, generation, and
  JavaScript-fence regressions are covered. Source commits `29a4a3f2` and
  `ea34b64f` add the fail-open lifecycle readers, collision-safe session
  writers, semantically safe task-ledger handling, and #894 regression. The
  corrected source head passed review and CI on
  [PR #887](https://github.com/nyldn/claude-octopus/pull/887), which squash
  merged as `99ee2c63` and closed the nine listed issues: #885, #886, and
  #888 through #894.

## Release v9.63.0

- [Release PR #895](https://github.com/nyldn/claude-octopus/pull/895)
  passed CodeRabbit, the Octopus PR-review gate, portability, smoke, symlinked
  path, macOS and Ubuntu unit, and full integration checks before squash merge
  `e35c7ecb`.
- Main Test Suite run `31626631725` passed on that exact squash commit before
  the annotated `v9.63.0` tag and non-prerelease GitHub Release were published.
  The shared `nyldn/plugins` marketplace was then updated to v9.63.0.
- A brand-new Claude process loaded the released `octo@nyldn-plugins` v9.63.0
  install inside the audited IA project and completed a prompt/session lifecycle
  with exit 0 and no UserPromptSubmit or SessionEnd hook errors.

## Host Diagnostics and Transcript Audit

- The recurring historical `UserPromptSubmit` exit 127 was not an Octopus
  hook. Archived Claude transcripts identify the Caveman hook command
  `Tracking caveman mode...` failing with `/bin/sh: node: command not found`
  under the GUI hook PATH. Caveman was disabled but still installed; it has now
  been uninstalled and a fresh Claude prompt completed without a
  UserPromptSubmit error. Already-running Claude processes may retain hooks
  loaded at startup until `/reload-plugins` or restart.
- A real-world design-record transcript showed strong evidence habits: Claude
  read the implementation before advising, preserved raw provider output after
  orchestration timeouts, visually inspected generated pages, found an internal
  path leak that text-only gates missed, and was transparent about provider
  failures. Its durable design conclusion was progressive emphasis rather than
  hiding primary content.
- The same audit showed avoidable orchestration cost: one parent session mixed
  repositories and workstreams for eleven days, delegated agents inherited a
  large unrelated plugin/skill context, provider presence was mistaken for
  usable quota, boilerplate unrelated to the task reached research prompts,
  and useful partial results were labelled only as timeouts. Product follow-up
  should keep delegated profiles lean, add quota-aware admission and circuit
  breaking, distinguish salvageable partial output, and make synthesis record
  agreements, conflicts, and evidence explicitly.

## Release v9.62.0

- **PR #873 / #868:** definition seats use realistic reasoning budgets instead
  of terminating mid-answer; squash merge `3a096728`.
- **PR #874 / #871:** preflight explicitly reports that legacy `gemini*` seats
  require AGY. Octopus does not restore direct Gemini CLI dispatch; squash merge
  `65960ced`.
- **PR #875 / #870:** grasp, ink, and embrace-gate check AGY fleet availability
  and retain safe empty-result synthesis fallbacks; squash merge `d7d74647`.
- **PR #876 / #869:** one wall-clock deadline covers every auth retry; timeout
  and termination exits are terminal, `TIMEOUT=0` stays unlimited, positive
  tangle implementer budgets have a configurable 1200-second floor, and
  recovered output is counted consistently. Restricted hosts receive the same
  effective phase budget. Positive bounded dispatches and continuation retries
  use the supervised subprocess because native Agent Teams exposes no
  plugin-accessible cancellation handle; squash merge `cc28531e`.
- **PR #879 / #872:** `progress.json` is a task-keyed monotonic ledger. Terminal
  totals are idempotent, estimated API spend is distinguished from subscription
  seats, phase and output identity reach every dispatch path, and the handoff
  reads the canonical file. `SubagentStop` and shell lifecycle writers share
  one atomic directory-lock protocol; squash merge `c5eb5bfb`.
- **PR #881 / #880:** atomic progress writes cannot replace caller EXIT, INT,
  or TERM traps. Bash 3.2 records the real lock owner, interrupted writes clean
  up and re-raise the signal, and abandoned initialization locks are reclaimable;
  squash merge `cc790499`. Exact `main` Test Suite run `31567827995` passed.
- **PR #883 / #882:** every Claude `--bare` authentication probe has a
  five-second default and hard 30-second total cap. The portable path supervises
  the complete process group, skips rather than launches when safe isolation is
  unavailable, and non-live tests never invoke the real provider. Exact PR head
  `79b3f7e7` passed 16/259/7 locally, Test Suite run `31573941934`, the Claude
  Octopus review workflow, and CodeRabbit approval. Squash merge `332282c8`
  passed exact `main` Test Suite run `31575017498`.
- Claude Code owns third-party marketplace mutation. Users enable automatic
  updates in `/plugin` under **Marketplaces → nyldn-plugins → Enable
  auto-update**, then run `/reload-plugins` or restart after an update. An
  installation older than v9.61.3 needs one manual marketplace/plugin update;
  a newer plugin cannot retroactively install itself into an older loaded copy.
- The v9.62.0 release-candidate tree passed `make sync-check`,
  `./scripts/validate-release.sh 9.62.0`, the handoff/README/version release
  regressions, and `OCTOPUS_DISABLE_BARE=1 make ci-local`: 16 smoke suites,
  259 unit suites, and 7 integration suites.
- Release review exposed that `sync-marketplace.sh` updated the Octopus entry
  but neither validated nor regenerated `.metadata.version`. The behavioral
  regression failed first with plugin `9.99.0` versus metadata `1.0.0`, then
  passed 17/17 after the generator and `--check` contract were corrected. The
  amended tree passed the complete 16/259/7 local gate again. Follow-up review
  confirmed that entry-only drift needed independent coverage and WARN-level
  diagnostics. The strengthened regression failed first against the raw-output
  path, then passed 17/17 after routing both version diagnostics through the
  logger; release wording now distinguishes generation from check-only
  validation. The final review strengthened the same fixture to prove update
  mode also repairs entry-only drift and that the repaired manifest passes a
  subsequent `--check`, with warning assertions derived from fixture data.

## Release v9.61.3

- **PR #854 / #838:** Direct Gemini CLI dispatch, detection, authentication, installer, model,
  pricing, generated command, and provider-documentation surfaces are removed.
  `gemini`, `gemini-fast`, and `gemini-*` remain compatibility inputs only and
  canonicalize to AGY; stale config is migrated one-way and the obsolete
  `.providers.gemini` object is deleted.
- The retired helper, Gemini provider overlay, Gemini command pack, and obsolete
  direct-provider tests are deleted. AGY is the sole Google-family execution
  seat in orchestration and agent configuration.
- The reported popup had a second concrete trigger: unescaped backticks around
  `agy login` in an unquoted help heredoc caused `help --full` to execute the
  login command. The text is now inert and a smoke regression proves help
  rendering cannot invoke provider login.
- **PR #856 / #851:** The permanent stale-install design adds local-only startup
  detection and cooldown guidance, doctor visibility, and explicit handoff to
  Claude Code's updater. Hooks must never perform network access, mutate the
  loaded cache, or launch an updater themselves.
- **PR #861 / #860:** Direct workflow command validation blocks Qwen when its
  credential is missing or expired, blocks retired Gemini, and rejects unsafe
  Codex command shapes. This prevents automation from opening provider login
  pages. The observed `https://chat.qwen.ai/` launch came from Qwen CLI device
  authorization after its OAuth token expired, not from a browser provider.
- **PR #857 / #841:** Interrupted probes now cancel and reap their owned process
  tree and clean phase state, traps, and temporary files without deleting
  unrelated user state.
- **PR #859 / #799:** One auth-aware provider predicate now owns availability,
  banner reporting, smoke health, and fleet admission, eliminating optimistic
  direct-binary checks.
- **PR #863 / #800 / #801:** Copilot delegates unpinned selection to CLI
  `auto`, Ollama selects only an installed local model, OpenRouter DeepSeek uses
  V4 Pro, generic OpenAI-compatible routing requires an explicit model, and a
  canonical catalog/pricing table drives both Bash and Python reports.
- **PRs #852 and #855:** Provider banners are auth-aware and default Codex
  prompts stay within the host CLI limit.
- Exact PR #863 head `a13223a9` passed Test Suite run `31452888521`: 16 smoke
  suites, 254 unit suites on Ubuntu, macOS, and a symlinked install path, plus
  7 integration suites. CodeRabbit approved with zero unresolved threads.
- The local Claude lifecycle test temporarily replaced the installed plugin as
  part of its normal uninstall/install coverage and finished successfully.
- An unrelated host hook failure was diagnosed as a stale `claude-mem` runtime;
  `claude-mem@13.15.0 repair` and `start` restored its worker. No external
  claude-mem files are part of this release.
- Release PR #858 exact head `cb66d485` passed Test Suite run `31455145611`:
  254 unit suites on Ubuntu, macOS, and a symlinked path, plus all smoke,
  integration, portability, and summary jobs. CodeRabbit approved with zero
  unresolved threads.
- PR #858 squash-merged as `47204470`. The exact `main` commit passed Test Suite
  run `31455875057` before annotated tag `v9.61.3` and the non-draft,
  non-prerelease GitHub Release were published.
- `scripts/sync-shared-marketplace.sh` pushed the Claude `octo` entry at
  v9.61.3 while preserving the Codex `claude-octopus` selector.
- Real host verification upgraded and enabled both `octo@nyldn-plugins` and
  `claude-octopus@nyldn-plugins` at v9.61.3. The stable
  `~/.claude-octopus/plugin` link resolves to the v9.61.3 Claude cache.
- **Post-release #865:** The Oracle `amy` E2E runner still asserted direct
  Gemini detection and probed Gemini after the provider was retired. Its
  durable source is the separate `nyldn/claude-octopus-dev` repository. PR #5
  there squash-merged as `218c3a7f` and the exact merged tree was deployed to
  `~/.octopus-e2e/e2e-command-test.sh` on `amy`.
- The runner now asserts an `agy:*` registration with no executable `gemini:*`
  seat, probes AGY rather than Gemini, and classifies approval, weekly/session
  limit, quota, auth, and capacity responses as infrastructure skips. The
  deployed regression test and targeted live AGY contract both passed. The
  pre-classifier full run reached B4 successfully; its sole 16/17 failure was
  the exact approval-wall response now covered by the merged classifier.

## Release v9.61.2

- Release vehicle: [PR #823](https://github.com/nyldn/claude-octopus/pull/823)
  squash-merged to `main` as `4301b60f` after being refreshed through main
  commit `52db2f8e` (PR #843).
- Exact combined-candidate `OCTOPUS_NON_INTERACTIVE=1 make ci-local` result:
  16 smoke suites, 248 unit suites, and 7 integration suites passed.
- `make sync`, `make sync-check`, `./scripts/validate-release.sh 9.61.2`,
  `bash tests/unit/test-handoff.sh`, `git diff --check`, and the executable-mode
  check passed. The exact PR-head Test Suite passed as run `31414428547`;
  CodeRabbit approved the head with zero unresolved threads.
- The exact squash commit's main-branch Test Suite passed as run `31415623371`.
  Annotated tag `v9.61.2` dereferences to `4301b60f`, and the non-draft,
  non-prerelease GitHub Release was published on 2026-08-10.
- `scripts/sync-shared-marketplace.sh` pushed the Claude `octo` entry at
  v9.61.2 while validating the stable Codex `claude-octopus` selector; its
  post-push check passed.
- Real installed-host verification started with enabled v9.61.1 copies.
  `codex plugin marketplace upgrade nyldn-plugins` plus `codex plugin add
  claude-octopus@nyldn-plugins` installed v9.61.2, while `claude plugin
  marketplace update nyldn-plugins` advanced `octo@nyldn-plugins` to v9.61.2
  and the explicit plugin update confirmed it was current.

## Included in v9.61.2

- **#816 / #819 merged (`53629216`, `3d3f972f`)** — Ollama, Copilot, and
  Vibe model pins and allowlists now reach dispatch instead of falling through
  to defaults or the unknown-provider allow arm. Issues #817 and #819 closed.
- **#820 merged (`104400d6`)** — restored the stable
  `claude-octopus@nyldn-plugins` Codex marketplace identity, added shared
  marketplace validation, and verified the real Claude/Codex symlink resolver.
  Issues #818 and #820 closed.
- **#824 merged (`3c4830aa`)** — skill-template tests now generate in an
  isolated copy instead of mutating the checkout. Issues #822 and #824 closed.
- **#826 merged (`5233de11`)** — council approval gates deny when automation
  lacks a controlling TTY even if inherited terminal signals are present.
  Issues #825 and #826 closed.
- **#828 merged (`8d879c24`)** — lifecycle timeout cleanup owns and reaps the
  hook process group without a `pkill` dependency. Issues #827 and #828 closed.
- **#830 merged (`e3e2f87c`)** — the release validator recognizes nested
  `SKILL.md` directories. Issues #829 and #830 closed.
- **#833 merged (`cf4ec6fd`)** — provider timeout evidence and every lifecycle
  duration assertion use true monotonic time; the production no-`timeout`
  fallback uses a reaped `sleep` watchdog instead of wall-clock-backed Bash
  `SECONDS`. Issues #832 and #837 closed.
- **#845 merged (`6cca4d3b`)** — the watchdog contract now requires creation,
  kill, and wait cleanup. Mutation testing proved deleting cleanup fails the
  case. Issue #844 closed.
- **#831 merged (`91f765be`)** — careful-mode SQL, `rm`, and whole-tree Git
  guards are scoped to executable context and token boundaries. Source-search,
  quoted-documentation, incomplete-SQL, dotfile, and subpath false positives
  stay quiet while actual destructive commands still fire. Issue #835 closed.
- **#842 merged (`e1be285b`)** — unknown agents fail closed without disabling
  supported Grok, Command Code, Atlas Cloud, or Vibe seats. Vibe credential
  parsing rejects blank/whitespace auth and handles TOML comments without
  dropping `#` inside quoted values. This addresses one bounded part of #799;
  #799 intentionally remains open.
- **#843 merged (`52db2f8e`)** — smoke-failed providers are removed from smart/full/minimal fleets,
  while a later PASS clears marker and expiry state immediately. The final
  minimal-strategy regression includes a real fake agy executable and is
  mutation-proven. Issue #840 closed.
- **#846 filed and fixed in v9.61.2** — the 248-suite macOS unit
  job exhausted the old 15-minute GitHub Actions ceiling while its individual
  tests were still passing. The unit matrix now has a 25-minute budget, guarded
  by a workflow-contract regression.
- **#836** — the update guide explains that Claude Code owns plugin updates,
  third-party marketplace auto-update is off by default, and users can enable
  it under `/plugin` -> Marketplaces -> `nyldn-plugins`; Codex retains its host
  marketplace upgrade flow. The plugin does not rewrite its own loaded cache or
  enablement state.
- **#838 was filed for the reported Gemini popup** and is addressed by the
  current post-v9.61.2 candidate. Its former requirement to preserve direct
  interactive Gemini use is superseded by the active `oco-004` decision that
  AGY is the sole Google-family execution seat.

Verification completed before the release candidate:

- PR #833 final local `make ci-local`: 16 smoke, 247 unit, and 7 integration
  suites passed; Linux, macOS, symlink, and integration checks also passed
  remotely.
- Lifecycle-focused suites: 10/10 and provider auth timeout 18/18.
- Careful-hook safety suite: 26/26 plus direct real-hook probes for quiet and
  destructive cases.
- Provider predicates: 13/13; Vibe 5/5; feature detection 20/20;
  OpenAI-compatible agent 19/19.
- Smoke dispatch exclusion: 9/9; quota watcher 2/2; embrace fail-fast 6/6;
  pre-retirement Gemini provider 52/52.
- Bash syntax, relevant ShellCheck gates, diff checks, and executable-mode
  checks were clean. Test-created stale worktree records were pruned.

## Delivered in v9.61.1 Cycle

- **#805 merged (`f0586e73`)** — added vendor-correct no-config model fallbacks
  for grok, OpenRouter, Vibe, and AtlasCloud, with behavioural regression tests.
  Fixes #797.
- **#806 closed** — duplicate of #805 and intentionally not merged.
- **#807 merged (`b449bebb`)** — migrates stale GPT-5.x pins, not only pre-GPT-5
  model IDs. Fixes #798.
- **#808 merged (`6df8d231`)** — prevents the Codex generator from deleting the
  hand-maintained `skill-council` and starter-pack directories.
- **#809 merged (`c9cfd8b2`)** — removes a GNU grep SIGPIPE failure from the
  agent-fields test under `set -o pipefail`.
- **#810 merged (`4ad6ddde`)** — flow-define streamlining pilot. Its final
  review pass made provider gating operational, clarified the terminal
  transition, scoped enforcement detection to real contract sections, and
  added caller-level generation regressions.
- **#812 merged (`3b658269`)** — final #804 reconciliation. Issue #804 closed
  automatically after the merge.
- **#813 merged (`144704b8`)** — addresses the valid #812 review findings with
  test-first workflow-state, design-lineage, allocation, and Codex metadata
  fixes. Its second review round adds bounded PROJECT.md file input, collision-
  safe design persistence, Fable self-fallback rejection, complete allocation
  rows, provider attribution, dial presets, and word-boundary UI descriptions.
  Its third review round makes unsupported runtime autonomy modes fail closed,
  completes intermediate-risk AI resolution, binds comparison boards to full
  returned variants, and checks persistence writes before validation and move.
  Its final approval follow-up serializes design-lineage allocation with an
  OS-managed per-branch lock so concurrent writers cannot fork the immutable
  revision chain, distinct branch names cannot alias the same lock, and
  terminated owners cannot leave a permanent lock.
  The request to chmod the Codex generator in CI was rejected because the tracked
  `100755` mode is an enforced repository contract that CI must not mask.

## PR #812 / Issue #804

The canonical `.claude/skills/` tree and generated `skills/` tree had real
content drift mixed with expected generator transformations. The reconciliation
does the following:

- Back-ports generated-only operational guidance into canonical sources for
  flow-deliver, flow-develop, flow-discover, security audit, UI/UX design,
  doctor, meta-prompt, parallel agents, and verification gate.
- Keeps expected name transformations such as `skill-ui-ux-design` to
  `octopus-ui-ux-design`; those are not drift.
- Treats `skill-intent-contract` as source-ahead and regenerates it.
- Removes the duplicate generated Iron Law from the `skill-verify` alias while
  retaining its rationalization table.
- Adds explicit Codex display-name and alias-description overrides rather than
  hand-editing generated frontmatter.
- Wires `build-codex-skills.sh` into `make sync`, `make sync-check`, and the
  portability CI job so future drift fails deterministically.

Verification on the final rebased code commit:

- `./scripts/build-codex-skills.sh --check`: 58 generated, 0 skipped, 0 errors;
  `skills/` up to date.
- `make ci-local`: 16 smoke, 245 unit, and 7 integration suites passed.
- No executable-bit changes.

Verification for the review follow-up:

- `0c5ba9eb` is the historical first-round code commit, not the current branch
  HEAD or the remote-equivalent state for PR #813. Its results are baseline
  evidence only.
- Second-round red baseline: workflow contracts failed 5 targeted cases,
  allocation failed 3, Codex generator failed 2, state manager failed 2, and
  Fable mode failed 2 before the corresponding changes.
- Third-round red baseline: allocation failed 2 targeted cases for runtime
  fail-closed handling and complete intermediate-risk resolution; workflow
  contracts failed 2 targeted cases for complete variant binding and checked
  design persistence before the corresponding changes.
- Final approval-follow-up red baseline: workflow contracts failed the targeted
  design-lineage serialization case before the per-branch lock was added.
- Final lock-hardening red baselines: the targeted contract failed before the
  directory lock was replaced with portable `flock` / `lockf` descriptor
  locking, and then the static and runtime cases failed before lock paths used
  a SHA-256 digest of the complete branch identity.
- Final focused results: `test-workflow-meta-contracts.sh` 13/13,
  `test-codex-enforcement-detection.sh` 6/6,
  `test-intent-contract-allocation.sh` 13/13, `test-octo-state.sh` 42/42, and
  `test-fable5-mode.sh` 29/29 passed.
- `test-handoff.sh`: 12/12 passed.
- `make sync-check`: passed; 58 Codex skills are up to date.
- `make ci-local`: 16 smoke, 245 unit, and 7 integration suites passed on the
  final PR branch HEAD after all code and handoff edits.
- The tested PR #813 head was `ba453bb3`; it was squash-merged as `144704b8`.
- No executable-bit changes.

The plugin-lifecycle integration test can overwrite canonical flow files in a
long-lived checkout from the currently installed marketplace copy. The full
gate therefore ran in a disposable detached worktree; its expected side effects
were removed with that worktree and did not contaminate the task branch.

## Release v9.61.1

- The release branch was refreshed from `upstream/main` after #810, #812, and
  #813 merged, then the v9.61.1 summary and changelog were expanded to cover the
  complete release scope.
- Release candidate commit `9f531d02` passed `make ci-local`: 16 smoke, 245
  unit, and 7 integration suites passed. The plugin-lifecycle test ran in a
  disposable detached worktree, which was removed with its expected fixture
  changes after the gate.
- `make sync-check` passed with 58 Codex skills up to date;
  `test-handoff.sh` passed 12/12; no executable-bit changes were introduced.
- PR #811 passed its remote checks and review gate, then squash-merged as
  `fad71488`.
- The exact merge commit passed the complete `main` Test Suite in run
  `31304191215`: portability, smoke, Linux and macOS unit, symlinked-path,
  integration, and final summary jobs all passed.
- The annotated `v9.61.1` tag peels to `fad71488`, and the non-draft,
  non-prerelease GitHub Release was published on 2026-08-09.

## Model Audit Closed in v9.61.3

- **#799:** PR #859 unified auth-aware availability, banner reporting, smoke
  health, and fleet admission behind the shared provider predicate.
- **#800:** PR #863 refreshed Copilot, Ollama, DeepSeek, and generic
  OpenAI-compatible defaults and fail-closed behavior.
- **#801:** PR #863 added the canonical model catalog and pricing table used by
  both Bash and Python reporting surfaces.

## Next Action

No issue-backed implementation remains; the live issue query was empty after
issue #882 closed with PR #883. Contributor PRs #867 (reasoning-role env-key
sanitization) and #877 (OrcaRouter provider) were intentionally not folded into
this issue-driven reliability release. Re-query their current review and base
state before acting on either one.

If streamlining work resumes, the unstarted candidates are:

1. Remaining streamlining work:
   - **4c:** remove obsolete drift detection, its unreachable duplicate, and
     the deprecated wizard only after confirming all call sites.
   - **4b:** cull unused/below-floor `SUPPORTS_*` flags together with the
     `sync-readme.py` parser change required when the set becomes empty.
   - **4d:** remove `tangle_reformat_decomposition` only after verifying whether
     current agy/Codex decomposition still needs weak-format repair.

Do not remove `lib/fable5.sh`, the Markdown-fence stripping in `review.sh`, or
the provider-outage fallback ladder in `review.sh`; each handles a current
runtime case rather than obsolete model weakness.

## Standing Constraints

- Bash floor is `/bin/bash` 3.2.57: no associative arrays or namerefs.
- Provider wiring uses the 7-point checklist in `docs/PROVIDERS.md`; provider
  case globs are order-sensitive (`claude-sdk*` before `claude*`).
- Regenerate owned artifacts through their scripts. Never hand-edit
  `.claude-plugin/marketplace.json`, `openclaw/src/tools/index.ts`, or generated
  `skills/` output.
- Run `make sync` after skill/provider/metadata changes and `make ci-local`
  before pushing code.
- Re-check script modes after local tests. The branch diff must contain no
  unintended mode changes.
- At session end, update this handoff, commit, pull/rebase, push, and verify the
  branch is up to date with its remote.
