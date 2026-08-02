# AI Agent Handoff

Last updated: 2026-08-02
Status: v9.57.0 released; two open PRs (#714 gemini marker fix, #713 test path fix)
Branch: `main`
Release: https://github.com/nyldn/claude-octopus/releases/tag/v9.57.0
Release squash: `37ba2af322766674b75d443126ce5b9005a81da4` (pushed to
`upstream/main`)
Tag target: `v9.57.0` is annotated, resolves to the same post-squash commit,
and is pushed

## Start Here

This file is the portable resume point for Claude Code, Codex, and other LLM
harnesses. It is a context packet, not the task tracker.

Read in order:

1. `AGENTS.md` and `RTK.md`
2. `git status --short --branch`
3. the latest commits on the current branch
4. the relevant `bd` issue before editing; if Beads is blocked, read
   `Tracking Blocker` below and do not migrate the database
5. `docs/MODEL-ROUTING-STRATEGY.md`
6. `docs/GPT-5.6-PROMPTING.md`

## Delivered Goal

Opus 5 is the default complex-work owner in Claude Octopus while keeping
Fable 5 as a capability escalation, Codex/GPT-5.6 as an independent peer,
cheaper model tiers, user overrides, and legacy compatibility.

## Decisions

- Opus 5 is the default premium Claude owner, not the only workflow model.
- Fable 5 is an explicit escalation and does not add an independent provider
  organization beside Opus.
- GPT-5.6 Sol is the default Codex peer; Terra and Luna are standard and budget
  tiers.
- Sonnet 5 is the standard Claude seat.
- Explicit user pins and role/phase routes remain higher priority than defaults.
- Claude model allowlists remain a compliance boundary: direct normal and fast
  Opus dispatch validate the final rerouted model and any fallback before
  command serialization.
- Tangle implementation isolation defaults on for orchestrated and direct
  library calls; explicit `OCTOPUS_TANGLE_RUN_WORKTREE=false` is the opt-out.
- Tangle uses one run ID across its branch, delegated tasks, markers, and
  validation artifacts, and resolves caller-relative ignored context before
  changing worktrees.
- Verification-only results fail closed unless all declared evidence members
  are strings and the baseline, reproduction, and implementation flags are
  internally consistent.
- Multi-model fan-out remains mandatory only for commands whose explicit
  contract is council, debate, parallel, or multi-provider research.
- Tests and runtime evidence remain mandatory; redundant prompt-only
  self-verification is removed.
- Release summaries, model defaults, component counts, runtime compatibility,
  and provider counts in the public README surfaces are generated from
  repository sources rather than maintained as duplicated prose.
- `make sync` repairs README drift and `make sync-check` rejects it. Release
  preparation updates the changelog first, then runs the same synchronization.
- Public test-suite counts are derived from the same `test-*.sh` discovery used
  by the smoke, unit, and integration runners.
- Review findings are fixed on the release branch before merge; review comments
  marked addressed are still checked against the actual head rather than
  accepted as evidence.
- `.octo-continue.md` predates this work and is preserved as user-owned state.

## Tracking Blocker

Beads is readable but not writable. The remote-backed database is on schema
v49 with four pending migrations to v53. Repository rules prohibit migrating
without the single designated migrator. No migration was run, so this work
could not be claimed or recorded as a new Beads issue.

## Current Evidence

- Public `main` includes the Council reliability queue, Tangle PRs #672-#675,
  and the Opus 5 routing squash from PR #678 (`972d9597`).
- Release v9.57.0 is the resume baseline. It adds the Command Code CLI
  provider (#696), selective Fable 5 escalation and authorship-aware review
  (#691), and the progressive feature-disclosure framework (#691); it fixes
  global flags after the subcommand (#706), helper-shim allowlist anchoring
  (#702), `USAGE_FILE` ordering (#694), Linux `stat` age checks and the
  provider quota-dead lifecycle (#690, #692).
- Release PR #711 squash-merged as
  `37ba2af322766674b75d443126ce5b9005a81da4`. The annotated `v9.57.0` tag
  peels to that exact public `main` commit, all required checks (Smoke, Unit,
  Integration on both platforms) passed on it, the GitHub release is
  published, and the shared `nyldn/plugins` marketplace advertises octo
  v9.57.0.
- Version choice was a minor, not the 9.56.2 patch that PR #707 proposed:
  #696 adds a provider and #691 adds hooks and env vars, which `RELEASING.md`
  step 1 classifies as additive. `config/features.json` independently declares
  `added_in: 9.57.0`, and the disclosure watermark compares that exact string.
  #707 was closed in favour of #711.
- Open at handoff: #714 forwards `WORKSPACE_DIR` into the `env -i` provider
  isolation so quota dead-marks written by `gemini-exec.sh` and `agy-exec.sh`
  are visible to the reader (they were landing under the `$HOME` fallback
  while readers used `$CLAUDE_PLUGIN_DATA`); #713 resolves a symlinked-checkout
  path mismatch in `test-feature-disclosure.sh`. Both verified locally.
- Known gap, not yet fixed: `gemini-via-agy` is `decision: none` / default `0`,
  so the migration path off the sunset Gemini Code Assist OAuth is never
  offered. Tracked in #715. Note the keychain dialog precedes
  `IneligibleTierError`, so a reactive dead-mark cannot suppress the first
  prompt of a session that reseats gemini — #714 is necessary but not
  sufficient.
- `Vendor Freshness` fails on `main` pushes (exit 2 on any warning) because the
  vendored `ui-ux-pro-max-skill` is one minor behind (v2.11.0 vs v2.12.0). Not
  a required check and unrelated to the release.
- Installed Claude Code: 2.1.220.
- Installed Codex CLI: 0.145.0.
- Upstream model policy: `nyldn/fable5-optimizer` v2.0.0.
- Targeted routing, resolver, provider activation, model config, SDK, Fable,
  execution-mechanism, marketplace-sync, smoke-version, and council tests pass.
- Latest focused evidence: Opus routing 21/21, Fable mode 27/27,
  SubagentStop 8/8, Tangle run-worktree 13/13, and verification-only 10/10.
- The final #675 head passed protected smoke, unit, and integration gates on
  Ubuntu and macOS.
- Fresh configs adopt the frontier roster; existing v3 configs and explicit
  model pins remain unchanged.
- `make sync-check` passes with no script mode changes.
- The primary checkout's tracked working tree is clean and its only local item
  is the preserved, user-owned untracked `.octo-continue.md`.
- `scripts/sync-readme.py` keeps `README.md`, `.claude-plugin/README.md`, and
  `PRODUCT.md` aligned with plugin metadata, runtime capability gates, model
  resolver defaults, test discovery, and the current changelog release.
- The README release-sync regression suite passes 8/8, including deliberate
  fixture drift detection, repair, and the cross-harness controller contract;
  current public model guidance names
  Opus 5, GPT-5.6 Sol/Terra/Luna, Sonnet 5, and opt-in Fable 5 consistently.
- `RTK.md` now provides the missing harness-neutral start/change/finish
  controller. `AGENTS.md` and `CLAUDE.md` identify the generated README
  surfaces and point agents to the same synchronization workflow.
- The final integrated `make ci-local` passed 16 smoke, 185 unit, and 7
  integration suites, including the live plugin lifecycle test.
- PRs #683, #684, and #685 passed protected/review checks, including Ubuntu and
  macOS unit matrices; the v9.56.0 release PR passed its required protected
  gates after all CodeRabbit findings were verified against the rebased head.
- PR #687 passed all protected and review checks with zero unresolved review
  threads. Exact-commit `main` Test Suite run 30310609791 then passed smoke,
  Ubuntu/macOS unit, integration, E2E, and summary gates before publication.

## Merge Queue

- Merged: #656, #658, #664, #666, #667, #668, #669, #670, #672, #673, #674,
  #675, #678, #681, #683, #684, release PR #677 (v9.54.2), release PR #680
  (v9.55.0), release PR #682 (v9.55.1), release PR #685 (v9.56.0), and review
  follow-up PR #686, and release PR #687 (v9.56.1).
- No public or private pull requests or issues remained open at release.
- Private E2E issue classification fix merged in
  `nyldn/claude-octopus-dev#4`; the target VPS remains unreachable over SSH, so
  the repository fix is complete but the live script has not been refreshed.

## Next Action

No delivery action remains. Future sessions should start from current `main`,
read this file and the routing strategy, then use `bd ready` for new work. The
private E2E repository fix is complete; retry the VPS refresh separately when
the host is reachable.
