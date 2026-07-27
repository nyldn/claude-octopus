# AI Agent Handoff

Last updated: 2026-07-27
Status: implementation verified; commit, rebase, push, and PR pending
Branch: `feat/opus-5-default-routing`

## Start Here

This file is the portable resume point for Claude Code, Codex, and other LLM
harnesses. It is a context packet, not the task tracker.

Read in order:

1. `AGENTS.md` and `RTK.md`
2. `docs/MODEL-ROUTING-STRATEGY.md`
3. `docs/GPT-5.6-PROMPTING.md`
4. `git status --short --branch`
5. the latest commits on the current branch

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

- Working branch was created from `upstream/main` at `c9e28f54`.
- Installed Claude Code: 2.1.220.
- Installed Codex CLI: 0.145.0.
- Upstream model policy: `nyldn/fable5-optimizer` v2.0.0.
- Targeted routing, resolver, provider activation, model config, SDK, Fable,
  execution-mechanism, marketplace-sync, smoke-version, and council tests pass.
- Fresh configs adopt the frontier roster; existing v3 configs and explicit
  model pins remain unchanged.
- `make sync-check` passes with no script mode changes.
- `make ci-local` passes: 16 smoke, 178 unit, and 7 integration suites; the
  probe dry-run timeout case is the suite's one expected skip.

## Next Action

Commit the scoped diff without the user-owned `.octo-continue.md`, resolve the
ready upstream issue/release queue, rebase on the resulting `upstream/main`,
push to `origin`, and open the upstream pull request. Update this section with
the final commit and PR.
