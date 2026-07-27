# AI Agent Handoff

Last updated: 2026-07-27
Status: prerequisites merged; final integrated verification passed
Branch: `feat/opus-5-default-routing`
Pull request: https://github.com/nyldn/claude-octopus/pull/678

## Start Here

This file is the portable resume point for Claude Code, Codex, and other LLM
harnesses. It is a context packet, not the task tracker.

Read in order:

1. `AGENTS.md` and `RTK.md`
2. the relevant `bd` issue before editing; if Beads is blocked, read
   `Tracking Blocker` below and do not migrate the database
3. `docs/MODEL-ROUTING-STRATEGY.md`
4. `docs/GPT-5.6-PROMPTING.md`
5. `git status --short --branch`
6. the latest commits on the current branch

## Current Goal

Make Opus 5 the default complex-work owner in Claude Octopus while keeping
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
- `.octo-continue.md` predates this work and is preserved as user-owned state.

## Tracking Blocker

Beads is readable but not writable. The remote-backed database is on schema
v49 with four pending migrations to v53. Repository rules prohibit migrating
without the single designated migrator. No migration was run, so this work
could not be claimed or recorded as a new Beads issue.

## Current Evidence

- Public `main` is complete through the Council reliability queue and Tangle
  PRs #673, #674, and #675 (`f3d7b276`).
- This branch includes that exact `main` squash stack; the only remaining
  public feature PR is #678.
- Core implementation commit: `6e0e6863` (`feat: adopt Opus 5 frontier model
  routing`); latest compliance fix: `4b96a2cf` (`fix: enforce Claude allowlists
  for Opus routing`).
- Installed Claude Code: 2.1.220.
- Installed Codex CLI: 0.145.0.
- Upstream model policy: `nyldn/fable5-optimizer` v2.0.0.
- Targeted routing, resolver, provider activation, model config, SDK, Fable,
  execution-mechanism, marketplace-sync, smoke-version, and council tests pass.
- Latest focused evidence: Opus routing 21/21, Fable mode 27/27,
  SubagentStop 8/8, Tangle run-worktree 13/13, and verification-only 10/10.
- The final #675 head passed protected smoke, unit, and integration gates on
  Ubuntu and macOS; the complete local unit matrix passed 183/183.
- Fresh configs adopt the frontier roster; existing v3 configs and explicit
  model pins remain unchanged.
- `make sync-check` passes with no script mode changes.
- The final integrated `make ci-local` passed 16 smoke, 183 unit, and 7
  integration suites, including the live plugin lifecycle test.

## Merge Queue

- Merged: #656, #658, #664, #666, #667, #668, #669, #670, #672, #673, #674,
  #675, and release PR #677 (v9.54.2).
- In progress: #678 (Opus 5 routing), followed by the v9.55.0 minor release.
- Private E2E issue classification fix merged in
  `nyldn/claude-octopus-dev#4`; the target VPS remains unreachable over SSH, so
  the repository fix is complete but the live script has not been refreshed.

## Next Action

Commit and push the integrated head to both remotes. Merge #678 only after
required review and protected verification gates pass. Finish the v9.55.0
minor release workflow, tag the squash-merge commit on `main`, publish the
GitHub release, and update this handoff to the released state.
