# AI Agent Handoff

Last updated: 2026-09-05

Status: PR [#1015](https://github.com/nyldn/claude-octopus/pull/1015) is the
only remaining public pull request. Its release branch has been rebased onto
`upstream/main` at `4c299eb3d214c771ce79f9823d382a5d8bc02048`, which includes
the merged PR #1014 review-snapshot fix. The first review batch is committed in
`46981fb`; the second is committed in `b801f56`; the integration follow-up is
`b07cffd`; and the final automated-review fixes are in the latest commit.

Branch: `release/v11.0.0`

Tracking: `bd` is unavailable in this checkout. Do not run a schema migration;
this handoff records the work instead.

Next action: wait for the 45-minute macOS shard gate, then squash-merge PR
#1015. Do not create the
v11 tag or GitHub release without separate authorization.

## Start Here

1. Run `git status --short --branch` and inspect the latest commits on the
   active branch before changing files.
2. Read the task references in `AGENTS.md` and this handoff.
3. Read the relevant `bd` issue when Beads is available. It is unavailable in
   this checkout; do not migrate its schema.

## Outstanding Implementation Work

- `tests/unit/test-openai-reasoning-fallback.py` still mocks
  `urllib.request.urlopen`, while the production helper now routes requests
  through `open_credentialed_request`. The standalone test is not reached by
  the current unit matrix and should be updated in a separate focused change.
- `tests/unit/test-skill-frontmatter.sh` prints a cosmetic `Failed Tests: 0`
  block while returning success. Its counters are correct, but the misleading
  summary should be cleaned up separately.
- Hosted `pr-review` currently has no available provider: Claude reached its
  temporary session cap and the Copilot fallback reached its monthly quota in
  run `33991524036`. Restore provider capacity or add an independent fallback.
- After this PR merges, the v11 tag, GitHub release, and any marketplace
  publication remain separate, authorization-gated release work.

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
- Dispatch-plan argv uses NUL-delimited transport, preserving embedded
  newlines without changing argument boundaries.
- Command validators now share the execution parser, and reserved usage rows
  are terminalized across all legacy persistence failures.
- Lock-recovery and dispatch-plan tests now report setup/helper failures
  through the test framework instead of passing or aborting silently.
- Review-fleet scoring rejects malformed reviewer collections cleanly instead
  of raising a Python traceback.
- The macOS unit shards now have a measured 45-minute budget after shard 1/2
  exceeded both the previous 20-minute limit and a 30-minute follow-up run.

## Model-routing decision

Fable 5.1 and GPT-6 Astra are cataloged at their premium token rates. They are
restricted to explicit, bounded escalation and are not defaults, routine
review seats, council members, or fallback models. This is deliberate: both
models are too expensive for automatic use.

## Verification

- Focused review suites pass: dispatch plan 11/11, model-aware seats 22/22,
  Doctor 19/19, runner sharding 7/7, audit follow-up 14/14, council
  contribution 8/8, packaging 7/7, and Codex safety 17/17 through its shell
  wrapper. Audit contract replay and fleet scoring pass 6/6.
- Related dispatch and lifecycle suites also pass: agent-command validation
  66/66, AGY provider 52/52, dispatch round trip 6/6, background and sync run
  contracts 28/28 each, probe-single 37/37, sandbox persistence 6/6, and tangle
  cancellation cleanup 16/16.
- `make ci-changed` failed closed to the full `make ci-local` matrix and exited
  0 on the final implementation tree in commit `069fd48`.
- `make sync-check`, `git diff --check`, and the executable-mode check pass.
- Hosted Ubuntu unit tests, macOS shard 2, smoke tests, portability, packaging,
  symlink-path coverage, and CodeRabbit passed on `069fd48`. MacOS shard 1 was
  cancelled by its former time limit, and `pr-review` exhausted both provider
  paths; neither failure reported a code or assertion defect.

## Workspace safety

The canonical checkout at `/Users/chris/git/claude-octopus-dev` remains
untouched, including its user-owned `.claude/settings.json` change. The
unrelated dirty `audit-followup` worktree must also be preserved. Only the
clean `pr-1015-finalizer` worktree may be removed after the PR is merged and
the branch is safely retained on the remote.
