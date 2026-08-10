# AI Agent Handoff

Last updated: 2026-08-10
Status: v9.61.2 is the active release, with permanent hook-timeout cleanup,
careful-mode false-positive fixes, Codex marketplace update recovery, and
provider availability/health hardening. The Gemini macOS keychain modal remains
tracked as future issue #838; cancellation cleanup remains #841.
Branch: `main`
Release: [v9.61.2](https://github.com/nyldn/claude-octopus/releases/tag/v9.61.2)

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

## Release v9.61.2

- Release vehicle: [PR #823](https://github.com/nyldn/claude-octopus/pull/823)
  on `release/v9.61.2`, refreshed through main commit `52db2f8e` (PR #843).
- Exact combined-candidate `OCTOPUS_NON_INTERACTIVE=1 make ci-local` result:
  16 smoke suites, 248 unit suites, and 7 integration suites passed.
- `make sync`, `make sync-check`, `./scripts/validate-release.sh 9.61.2`,
  `bash tests/unit/test-handoff.sh`, `git diff --check`, and the executable-mode
  check passed. Release validation reported only the two expected pre-release
  warnings: the tag and GitHub Release do not exist until PR #823 is merged.
- PR #843's current-head remote matrix passed on Ubuntu, macOS, the symlinked
  install path, and integration tests; CodeRabbit approved it with zero
  unresolved threads.
- Publication must follow `RELEASING.md`: squash-merge PR #823, wait for the
  exact main commit's Test Suite, tag that squash commit as `v9.61.2`, create
  the GitHub Release, sync `nyldn/plugins`, and verify real Claude and Codex
  upgrades from the installed v9.61.1 baseline.

## Delivered in v9.61.2 Cycle

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
- **#846 filed and fixed in the release candidate** — the 248-suite macOS unit
  job exhausted the old 15-minute GitHub Actions ceiling while its individual
  tests were still passing. The unit matrix now has a 25-minute budget, guarded
  by a workflow-contract regression.
- **#836** — the update guide explains that Claude Code owns plugin updates,
  third-party marketplace auto-update is off by default, and users can enable
  it under `/plugin` -> Marketplaces -> `nyldn-plugins`; Codex retains its host
  marketplace upgrade flow. The plugin does not rewrite its own loaded cache or
  enablement state.
- **#838 filed for the reported Gemini popup** — unattended workflow dispatch
  can still trigger macOS Keychain access for `gemini-cli-workspace-oauth` via
  the Node-based Gemini CLI. The issue records the screenshot text, suspected
  detection/config paths, and non-prompting acceptance criteria. It is a future
  task, not part of v9.61.2.

Verification completed before the release candidate:

- PR #833 final local `make ci-local`: 16 smoke, 247 unit, and 7 integration
  suites passed; Linux, macOS, symlink, and integration checks also passed
  remotely.
- Lifecycle focused suites: 10/10 and provider auth timeout 18/18.
- Careful-hook safety suite: 26/26 plus direct real-hook probes for quiet and
  destructive cases.
- Provider predicates: 13/13; Vibe 5/5; feature detection 20/20;
  OpenAI-compatible agent 19/19.
- Smoke dispatch exclusion: 9/9; quota watcher 2/2; embrace fail-fast 6/6;
  Gemini provider 52/52.
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

## Model Audit Still Open

- **#799 — provider availability/auth parity.** `check-providers.sh` still uses
  binary presence alone for several providers, while preflight has stronger
  auth checks. PR #842 fixed `is_agent_available_v2`'s optimistic default and
  added missing explicit contracts; do not close #799 until the remaining
  active detection surfaces agree.
- **#800 — stale pins and dead environment overrides.** Copilot and Ollama have
  stale defaults/version floors. The missing Ollama/Copilot/Vibe model and
  allowlist wiring was fixed in #816/#819, but the broader issue remains.
- **#801 — catalog and price-table consolidation.** Model membership, tiering,
  and pricing still disagree across `models.sh`, `octo-model-config.sh`,
  `cost.sh`, and `usage-report.sh`.

Each issue contains a concrete reproduction. Do not combine them into one large
provider refactor; preserve the behavioural-test-first pattern used by `#805` and
`#807`.

## Next Action

1. **#838:** reproduce the current Gemini CLI macOS Keychain behavior and make
   unattended dispatch fail closed before any prompt-capable OAuth invocation.
   Correct the current false "keychain bypass active" assurance and preserve
   explicit interactive use.
2. **#841:** add workflow cancellation cleanup for provider trees, PID and
   heartbeat registries, incomplete result stubs, terminal events, and
   project-local state pollution.
3. Continue #799, #800, and #801 as separate test-first fixes; do not reopen
   the bounded portions already delivered in v9.61.2.
4. Revisit #815 alongside #838 for Gemini environment-level E2E coverage.
5. Remaining streamlining work is still unstarted:
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
