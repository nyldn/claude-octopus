# AI Agent Handoff

Last updated: 2026-09-05

Status: PR [#1015](https://github.com/nyldn/claude-octopus/pull/1015) is the
only remaining public pull request. Its release branch has been rebased onto
`upstream/main` at `4c299eb3d214c771ce79f9823d382a5d8bc02048`, which includes
the merged PR #1014 review-snapshot fix. Seven valid CodeRabbit findings are
fixed in local commit `46981fbcc17624712ff7855d8c4ec0c0f45d0f2a`.

Branch: `release/v11.0.0`

Tracking: `bd` is unavailable in this checkout. Do not run a schema migration;
this handoff records the work instead.

Next action: validate this handoff-only change, push the rebased branch with
`--force-with-lease`, resolve only the seven verified review threads, wait for
exact-head hosted checks and review, then squash-merge PR #1015. Do not create
the v11 tag or GitHub release without separate authorization.

## Review fixes

- Dispatch plans now carry serialized argv instead of splitting a scalar
  command. The parser preserves quoted, escaped, and empty arguments without
  using `eval`.
- Qualified `agy:model` selections pass the exact requested model through
  `OCTOPUS_AGY_MODEL`.
- Doctor detects Git checkouts without a `grep -q` pipeline under `pipefail`.
- The test runner rejects stale, missing, and non-unit symlink-sensitive suite
  entries.
- The packaging fixture checks prerequisites, keeps npm diagnostics, and
  cleans its bounded temporary directory.
- The Python safety-contract suite now lives in a Python file; its shell entry
  uses the repository test framework.
- Council contribution tests guard digest and record command substitutions so
  `set -e` cannot abort before reporting a useful failure.

## Model-routing decision

Fable 5.1 and GPT-6 Astra are cataloged at their premium token rates. They are
restricted to explicit, bounded escalation and are not defaults, routine
review seats, council members, or fallback models. This is deliberate: both
models are too expensive for automatic use.

## Verification

- Focused review suites pass: dispatch plan 10/10, model-aware seats 22/22,
  Doctor 19/19, runner sharding 7/7, audit follow-up 13/13, council
  contribution 8/8, packaging 7/7, and Codex safety 17/17 through its shell
  wrapper.
- Related dispatch and lifecycle suites also pass: agent-command validation
  63/63, AGY provider 52/52, dispatch round trip 6/6, background and sync run
  contracts 28/28 each, probe-single 37/37, sandbox persistence 6/6, and tangle
  cancellation cleanup 16/16.
- `make ci-changed` failed closed to the full `make ci-local` matrix and exited
  0 on the exact implementation tree in commit `46981fb`.
- `make sync-check`, `git diff --check`, and the executable-mode check pass.

## Workspace safety

The canonical checkout at `/Users/chris/git/claude-octopus-dev` remains
untouched, including its user-owned `.claude/settings.json` change. The
unrelated dirty `audit-followup` worktree must also be preserved. Only the
clean `pr-1015-finalizer` worktree may be removed after the PR is merged and
the branch is safely retained on the remote.
