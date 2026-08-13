# AI Agent Handoff

Last updated: 2026-08-13
Status: Issue #898 is implemented and passes the complete local gate on branch
`fix/898-explicit-activation`; PR, merge, and release are the remaining steps.
Octopus is now dormant until explicit invocation. Native command/skill gates,
session-affine workflow hooks, passive startup notices, host-filtered tool
hooks, and opt-in automation replace the previous install-wide engagement.
The stable plugin entrypoint also advances to the host-loaded version so an old
but still-present cache cannot strand explicit commands on stale hooks.
Branch: `fix/898-explicit-activation`
Current release: [v9.63.0](https://github.com/nyldn/claude-octopus/releases/tag/v9.63.0)
Tracking: [issue #898](https://github.com/nyldn/claude-octopus/issues/898)

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
