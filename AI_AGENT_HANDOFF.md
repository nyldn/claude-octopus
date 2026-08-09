# AI Agent Handoff

Last updated: 2026-08-09
Status: v9.61.1 packages the completed model-routing, generator-safety,
flow-define, and #804 skill-tree work in release PR #811. Treat GitHub as the
source of truth for the PR, tag, and release state, and finish that release
workflow before starting new work. Issues #799-#801 and streamlining Parts
4b/4c/4d remain unstarted.
Branch: `release/v9.61.1`
Release: not yet tagged — pending PR #811 merge, see "Next Action" below

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

Beads is readable but not writable. The remote-backed database is on schema
v49 with four pending migrations to v53. Repository rules reserve migration for
the designated migrator. No migration was run, so this work could not be
claimed or recorded in `bd`; use this handoff for the blocked tracking record.

## Delivered in This Cycle

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

## Release PR #811

- The release branch was refreshed from `upstream/main` after #810, #812, and
  #813 merged, then the v9.61.1 summary and changelog were expanded to cover the
  complete release scope.
- Release candidate commit `9f531d02` passed `make ci-local`: 16 smoke, 245
  unit, and 7 integration suites passed. The plugin-lifecycle test ran in a
  disposable detached worktree, which was removed with its expected fixture
  changes after the gate.
- `make sync-check` passed with 58 Codex skills up to date;
  `test-handoff.sh` passed 12/12; no executable-bit changes were introduced.
- Remote checks and the review gate still apply to the final PR head. After the
  squash merge, wait for the exact `main` Test Suite commit before tagging or
  publishing the GitHub Release.

## Model Audit Still Open

- **#799 — provider availability/auth parity.** `check-providers.sh` still uses
  binary presence alone for several providers, while preflight has stronger
  auth checks. `is_agent_available_v2` also has an optimistic default arm.
- **#800 — stale pins and dead environment overrides.** Copilot and Ollama have
  stale defaults, and some provider IDs do not map to their documented
  `OCTOPUS_*_MODEL` variables.
- **#801 — catalog and price-table consolidation.** Model membership, tiering,
  and pricing still disagree across `models.sh`, `octo-model-config.sh`,
  `cost.sh`, and `usage-report.sh`.

Each issue contains a concrete reproduction. Do not combine them into one large
provider refactor; preserve the behavioural-test-first pattern used by `#805` and
`#807`.

## Next Action

1. Check the live state of release PR #811. If open, merge only after local and
   remote gates pass. If closed without merging, record that outcome and stop.
   If merged, verify the exact squash commit passes the `main` Test Suite, the
   annotated `v9.61.1` tag points to it, and the GitHub Release exists.
2. Pick up #799, #800, and #801 as separate test-first fixes.
3. Remaining streamlining work is still unstarted:
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
