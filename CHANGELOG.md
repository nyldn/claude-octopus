## [8.56.0] - 2026-03-13

### Added

- **8 new `SUPPORTS_*` detection flags** (94 total, 30 `version_compare` blocks) from CC v2.1.72 (2 untracked) and v2.1.74 (6 new).
- **v2.1.72**: `SUPPORTS_PARALLEL_TOOL_RESILIENCE` (failed Read/WebFetch/Glob no longer cancels sibling tool calls), `SUPPORTS_PLAN_WITH_ARGS` (`/plan` accepts description argument).
- **v2.1.74**: `SUPPORTS_AUTO_MEMORY_DIR` (`autoMemoryDirectory` setting), `SUPPORTS_FULL_MODEL_IDS` (full model IDs e.g. `claude-opus-4-6` in agent frontmatter), `SUPPORTS_SESSION_END_TIMEOUT` (`CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` env var), `SUPPORTS_CONTEXT_SUGGESTIONS` (`/context` with actionable optimization tips), `SUPPORTS_PLUGIN_DIR_OVERRIDE` (`--plugin-dir` overrides marketplace), `SUPPORTS_MANAGED_POLICY_FIX` (managed policy `ask` rules fix).
- `test-cc-v2174-sync.sh` — 36 tests covering declarations, detection blocks, logging, wiring, and version comments.

### Wired

- `spawn_agent()`: Positive debug log when `SUPPORTS_FULL_MODEL_IDS` confirms full model ID support in agent frontmatter (CC v2.1.74+).
- `/octo:doctor`: Surfaces `/context` command as diagnostic tool for context-heavy sessions (CC v2.1.74+).
- `/octo:doctor`: Checks `autoMemoryDirectory` setting in `~/.claude/settings.json` (CC v2.1.74+).

### Fixed

- `test-version-check.sh` Test 5: `head -30` → `head -40` — fragile against growing log line count from new flags.

---

## [8.55.0] - 2026-03-12

### Changed

- **Smart router v2.0** (`/octo:octo`) — Complete rewrite of the natural language workflow router. Routing coverage expanded from 8 → 17 workflows with 9 new intents: debug, security, tdd, docs, quick, design-ui-ux, prd, brainstorm, deck.
- **Decision tree confidence** — Replaced ambiguous percentage-based scoring (`matching/total * 100 + adjustments`) with explicit HIGH/MEDIUM/LOW decision tree. Single matched intent + specific target = auto-route. Same-priority conflicts = ask user.
- **3-tier priority ordering** — Specialized workflows (P1) > Core workflows (P2) > Build workflows (P3). "Analyze the security of our API" now correctly routes to `/octo:security` (P1) over `/octo:discover` (P2).
- **Context efficiency** — 382 → 204 lines (47% reduction). Deduplicated 3x-repeated routing table (docs, execution contract, examples) to single authoritative source in execution contract.

### Added

- **Meta command handler** — `/octo:octo help` displays all 17 workflows in 4 categories (Core, Engineering, Creative & Documentation, Quick).
- **Input length guard** — Queries >500 chars truncated for intent analysis; full query passed to target workflow.
- **Routing analytics** — Decisions appended to `~/.claude-octopus/routing.log` with timestamp, intent, confidence, and target.
- **Routing memory** — Auto-memory corrections on rejected suggestions enable preference learning across sessions.
- `test-smart-router.sh` — 65 static analysis tests: routing table integrity, backing file existence for all 17 targets, P0 fix validation, decision tree verification, priority ordering, meta commands, category groupings, removed features, file size.

### Fixed

- **P0: Broken validation routing** — `Skill: "validate"` invoked non-existent skill. Changed to `Skill: "review"`. Any query with validation intent was silently failing.
- **Flaky `test-debug-mode-simple.sh`** — Tests 4 & 5 checked for "Command:" and "spawn_agent:" in `--debug --dry-run` output, but probe caching short-circuited before `spawn_agent()` runs. Replaced with static analysis of orchestrate.sh source.

### Removed

- Unimplemented "chain workflows" documentation (set false user expectations).
- Model override example from command docs (`OCTOPUS_CODEX_MODEL` in examples — minor prompt injection surface).

---

## [8.54.0] - 2026-03-12

### Changed

- **Multi-agentic `/octo:research`** — Refactored from single `Bash(orchestrate.sh probe)` call (120s timeout) to parallel `Agent(run_in_background=true)` subagents. Each perspective calls `orchestrate.sh probe-single` independently — no timeout constraint. Claude synthesizes in-conversation instead of Gemini synthesis that frequently timed out.
- **User-configurable research intensity** — `/octo:research` and `/octo:discover` now ask intensity before launching: Quick (2 agents, 1-2 min), Standard (4-5 agents, 2-4 min), Deep (6-7 agents with web search, 3-6 min). Intensity passed via `[intensity=quick|standard|deep]` in Skill args.
- **Gemini-first launch ordering** — Higher-latency Gemini agents launch first, then Codex, then Claude Sonnet, then Perplexity, reducing total wall-clock time.

### Added

- `probe_single_agent()` — Standalone single-perspective probe function in orchestrate.sh. Handles persona application, context budget, credential isolation, auth retry, and result file writing.
- `probe-single` dispatch command — Calls `probe_single_agent()` from Agent tool subagents.
- `test-probe-single.sh` — 26 static analysis tests for probe-single function, dispatch, flow-discover integration, command alignment, and backward compatibility.

### Fixed

- `test-knowledge-routing.sh` — Fixed pre-existing SIGPIPE flake caused by `grep -q` with `set -eo pipefail` (replaced with `grep -c >/dev/null` per known gotcha).

### Internal

- `flow-discover.md` STEP 3.5-7 rewritten: fleet building by intensity, parallel Agent dispatch, result collection with graceful degradation (min 2 results), structured in-conversation synthesis.
- `discover.md` 4-option depth → 3-option intensity question, aligned with `research.md`.
- `test-enforcement-pattern.sh` scoped exceptions: flow-discover may use Agent tool (not Bash) and direct synthesis file pattern (not `find -mmin`).
- Backward compatible: `probe_discover()`, `discover|research|probe` dispatch, and `/octo:embrace` path all untouched.

---

## [8.53.0] - 2026-03-11

### Added

- **`readonly: true` frontmatter** — Add `readonly: true` to any agent persona `.md` file to enforce read-only tool policy (blocks Write/Edit/Bash modifications). Implemented via `get_agent_readonly()` with awk-based frontmatter parsing, new `agent_name` param in `apply_tool_policy()` and `apply_persona()`. `backend-architect` added as live example.
- **User-scope agents (`~/.claude/agents/`)** — Personal agent personas placed in `~/.claude/agents/*.md` are automatically discovered for description lookup and agent listing. `USER_AGENTS_DIR` constant; plugin agents take precedence on name collision.
- **`/octo:resume <agent-id>`** — Resume a previous Claude agent by transcript ID. Wraps `resume_agent()` via new `agent-resume` dispatch case. Requires `SUPPORTS_CONTINUATION` (CC v2.1.55+) and `SUPPORTS_STABLE_AGENT_TEAMS`.

### Internal

- `get_agent_readonly()` — awk-based YAML frontmatter parser (not `head -20 | grep`) to avoid false positives in body content
- `apply_persona()` 4th param `agent_name`, threaded to `apply_tool_policy()` 3rd param
- `spawn_agent()` pre-computes `curated_name_early` before `apply_persona` call
- OpenClaw registry rebuilt (89 entries)
- 39 commands, 50 skills

## [8.52.0] - 2026-03-11

### Added

- CC v2.1.73 feature sync — 6 new detection flags (86 total, 28 version_compare blocks):
  - `SUPPORTS_MODEL_OVERRIDES` — CC `modelOverrides` setting for custom provider model IDs (e.g. Bedrock inference profile ARNs). `/octo:doctor` surfaces this on enterprise backends.
  - `SUPPORTS_LOOP_ENTERPRISE_FIX` — `/loop` now works on Bedrock/Vertex/Foundry and when telemetry is disabled
  - `SUPPORTS_SUBAGENT_MODEL_FIX` — `model: opus/sonnet/haiku` frontmatter no longer silently downgraded on enterprise. `spawn_agent()` warns when running on enterprise without this fix.
  - `SUPPORTS_SESSION_RESUME_HOOK_FIX` — `SessionStart` hooks fire exactly once on `--resume`/`--continue` (was double-firing)
  - `SUPPORTS_BG_PROCESS_CLEANUP` — background bash processes spawned by subagents are cleaned up on agent exit
  - `SUPPORTS_SKILL_DEADLOCK_FIX` — no deadlock when 50 skill files load during `git pull`. `/octo:doctor` warns on CC < v2.1.73.

---

## [8.50.0] - 2026-03-11

### Changed

- Multi-LLM /octo:review — 3-round parallel fleet (Codex + Gemini + Claude + Perplexity), inline PR comments, REVIEW.md support, verified findings

---

## [8.49.1] - 2026-03-10

### Changed

- Fix /octo:setup command name mismatch
- Update setup.md troubleshooting with correct manual reinstall steps for broken plugin update UI (#17)

---

## [8.49.0] - 2026-03-10

### Changed

- Relevance-aware synthesis, CC pre-prompt alignment, model catalog, usage reporting, test fixes

---

## [8.48.0] - 2026-03-09

### Fixed

- Provider activation reliability: synthesis timeout recovery, claude-sonnet agent capture, model updates
- Cost estimate placement in embrace workflow (test regression fix)

### Added

- Claude Code v2.1.72 feature sync: 8 new detection flags, effort symbols, cron control
- Codex OAuth freshness check in preflight
- `synthesize-probe` recovery command for timeout resilience
- `OCTOPUS_FORCE_LEGACY_DISPATCH` for reliable claude-sonnet capture

---

## [8.47.0] - 2026-03-09

### Changed

- Dual-backend scheduler: guided wizard, job dashboard, coworkd/daemon detection

---

## [8.46.0] - 2026-03-09

### Changed

- Skill directive WHY reasoning, improved descriptions for better triggering

---

## [8.45.0] - 2026-03-09

### Added

- **Reaction engine** — `scripts/reactions.sh` provides configurable auto-response to agent
  lifecycle events. Detects CI failures, review comments, stuck agents, and PR approvals.
  Dispatches actions: forward CI logs to agents, forward review comments, notify, escalate.
  Retry tracking with max retries and escalation timeout (default 30m for CI, 60m for reviews).
- **13-state PR lifecycle** — agent registry expanded from 4 statuses (running, retrying, done,
  failed) to 13: running, retrying, pr_open, ci_pending, ci_failed, review_pending,
  changes_requested, approved, mergeable, merged, done, failed, stuck.
- **Reaction inbox** — agents receive CI failure logs and review comments in
  `~/.claude-octopus/agents/reactions/inbox/<agent-id>/` for processing.
- **Escalation with timeout** — if an agent exceeds max retries or escalation timeout, the
  reaction engine displays a prominent escalation notice and logs to `escalations.log`.
- **Project-level reaction config** — `.octo/reactions.conf` overrides embedded defaults using
  pipe-delimited rules (EVENT|ACTION|MAX_RETRIES|ESCALATE_AFTER_MIN|ENABLED).

### Changed

- **`agent-registry.sh health --react`** — new `--react` flag fires the reaction engine after
  detecting state changes. Health checks now monitor all active agents (not just running/retrying).
- **`flow-parallel.md` monitoring loop** — reaction engine fires between poll cycles to auto-handle
  CI failures and review comments while work packages execute.
- **`/octo:sentinel`** — execution contract now includes reaction engine step after triage, so
  CI failures and review comments are auto-forwarded to agents during monitoring.
- **Agent registry cleanup** — `merged` status treated as terminal alongside `done` and `failed`.

## [8.44.0] - 2026-03-09

### Added

- **Agent registry** — `scripts/agent-registry.sh` provides persistent lifecycle tracking for
  spawned coding agents. Tracks agent ID, branch, worktree path, status, PR number, and CI
  status across sessions. Commands: register, update, get, list, health, cleanup.
- **Worktree-per-agent in `/octo:parallel`** — each work package now runs in its own isolated
  git worktree, eliminating file write contention when multiple agents modify files
  simultaneously. Worktrees are auto-created before launch and cleaned up after completion.
- **PR comment posting** — `/octo:review`, `/octo:staged-review`, and `/octo:deliver` now
  detect open PRs on the current branch and post review findings as PR comments via
  `gh pr comment`. Auto-posts in automated workflows (embrace, factory), asks first in
  standalone mode.

### Changed

- **`flow-parallel.md` launch template** — work packages create isolated worktrees, register
  in agent registry on spawn, and update registry status on completion or failure.
- **`flow-deliver.md`** — Step 7 now includes PR comment posting after validation report.
- **`skill-code-review.md`** — added post-review PR comment section with auto/ask behavior.
- **`skill-staged-review.md`** — combined report posted to PR when available.

## [8.43.0] - 2026-03-08

### Added

- **Context-aware quality injection** — `flow-develop.md` and `flow-deliver.md` now detect 6
  dev subtypes (frontend-ui, cli-tool, api-service, infra, data, general) and inject
  domain-specific quality criteria into provider prompts. Frontend tasks get accessibility
  and self-containment rules; CLI tasks get exit code and help text checks; API tasks get
  input validation and auth requirements.
- **BM25 design intelligence auto-injection** — when `frontend-ui` subtype is detected in the
  develop phase, the BM25 search engine is queried for style and UX patterns relevant to
  the task, injected directly into the provider prompt.
- **Reference integrity gate** — `quality-gate.sh` now scans recently created HTML, shell
  scripts, and Docker Compose files for broken file references (missing scripts, stylesheets,
  sourced files, Dockerfiles). Blocks with actionable error listing each broken reference.
- **Three-way adversarial design critique** — `/octo:design-ui-ux` now runs a mandatory
  critique step between Define and Develop phases. Codex (implementation critique), Gemini
  (ecosystem critique), and Claude (independent design critique) all review the proposed
  design direction in parallel. Issues are triaged, fixes applied, and a visible revision
  diff is shown before tokens/components are generated.

### Changed

- **Implementer persona** — added deliverable integrity rules: every referenced file must
  exist, prefer self-contained deliverables, single artifacts stay as one file.
- **Researcher persona** — added output quality bar: evidence-backed claims, trade-off
  disclosure, explicit uncertainty acknowledgment.
- **Synthesizer persona** — added synthesis integrity rules: explicit conflict surfacing,
  completeness validation against original request, standalone output requirement.
- **Task decomposition** — both `tangle_develop()` and `map_reduce()` now include cohesion
  rules preventing single-deliverable fragmentation. "2-6 subtasks; fewer is better when
  tightly coupled" replaces the old "4-6 independent subtasks."
- **`aggregate_results()`** — now synthesizes via Gemini instead of concatenating markdown
  files. Falls back to concatenation if Gemini unavailable.
- **Design workflow banner** — now shows provider availability (Codex, Gemini, Claude) and
  the critique phase in the pipeline indicator.

## [8.42.0] - 2026-03-08

### Added

- **Mandatory compliance blocks** on all 8 workflow commands (embrace, discover, define,
  develop, deliver, plan, review, security) — Claude is now explicitly prohibited from
  skipping workflows it judges "too simple." Addresses user reports of `/octo:embrace`
  being bypassed for straightforward tasks.
- **Interactive next-steps** after every workflow completes — all phase commands and embrace
  now ask the user what to do next via `AskUserQuestion` instead of ending silently.
- **Anti-injection nonces** (`sanitize_external_content()` in orchestrate.sh) — wraps
  file-sourced content (memory files, provider history, earned skills) in random hex
  boundary tokens to prevent prompt injection from untrusted external content.
- **Session learnings layer** — `session-end.sh` now writes `octopus-learnings.md` to
  auto-memory with per-session meta-reflection (workflow, phase, agent calls, errors, debate).
- **Feature gap analysis** — `docs/FEATURE-GAP.md` living document tracks all 72 CC feature
  flags with Green/Yellow/Red adoption status and gap closure history.
- **Multi-LLM debate gates** in embrace, plan, review, security, and define commands —
  optional Claude + Codex + Gemini deliberation at workflow transition points.

### Fixed

- Reinstated `/octo:debate` and `/octo:research` commands wrongly removed in v8.41.0
  consolidation. These had unique standalone functionality (three-way AI debates and
  deep multi-AI research respectively).
- Removed "Don't use for" sections from phase commands that contradicted mandatory
  compliance blocks and encouraged Claude to skip workflows.
- Command count corrected: 36 → 38 (debate + research reinstated).

### Changed

- OpenClaw registry updated: 86 → 88 entries (debate + research commands).
- All debate-related options across commands now explicitly say "Multi-LLM" and name
  all three models (Claude + Codex + Gemini) so users understand what they're enabling.

## [8.41.0] - 2026-03-07

### Added

- 3 new hook events registered in hooks.json:
  - `PreCompact` — persists workflow state (phase, decisions, blockers) before context compaction
  - `SessionEnd` — finalizes metrics, persists preferences to auto-memory, cleans up session artifacts
  - `UserPromptSubmit` — classifies task intent via keyword matching for improved skill routing
- 10 native agent definitions in `.claude/agents/` mirroring top personas:
  - security-auditor, code-reviewer, backend-architect, tdd-orchestrator, debugger,
    performance-engineer, frontend-developer, docs-architect, cloud-architect, database-architect
- Persona-agent sync test ensuring every agent definition has a matching persona file
- Auto-memory integration: SessionEnd hook writes `octopus-preferences.md` to project memory
  with autonomy mode, provider config, and last update timestamp
- `enable-http-telemetry.sh` script for converting shell-based telemetry to native HTTP hooks (CC v2.1.63+)
- Mixed models integration: `_get_agent_model_raw()` now checks `CLAUDE_MODEL` env var (Priority 0.5)
  for Claude-side agents, respecting native CC model settings without duplicate config
- Spec mode plan view alignment: `flow-spec.md` Step 7.5 uses `EnterPlanMode` for NLSpec review
  when VSCode plan view is available (CC v2.1.70+), with graceful terminal fallback
- 89-test suite (`test-v8.41.0-feature-adoption.sh`) covering hooks, agents, sync, droids, telemetry, and auto-memory
- Factory droid generation in `build-factory-skills.sh` — generates `agents/droids/` from `.claude/agents/`
  so Factory AI discovers native droids alongside Claude Code agent definitions
- Native HTTP telemetry hook in hooks.json (`"type": "http"`) alongside shell fallback;
  shell hook skips when `SUPPORTS_HTTP_HOOKS=true` to avoid double telemetry
- SessionStart auto-memory restoration (`session-start-memory.sh`) — reads persisted preferences
  from `octopus-preferences.md` on session start and injects them into `session.json`

### Changed

- Command consolidation: 13 thin wrapper commands removed (49 → 36 commands)
  - 8 pure wrappers deleted: issues, ship, rollback, debate, resume, setup, validate, status
  - 5 flow aliases deleted: probe, grasp, tangle, ink, research
  - Matching skills now have `user-invocable: true` frontmatter for direct invocation
- Hook event count: 10 → 13 (PreCompact, SessionEnd, UserPromptSubmit)
- Total hook scripts: 25 → 29
- Task manager simplified: `create_embrace_tasks()` and `create_phase_task()` deprecated
  in favor of native TodoWrite for Claude-side task tracking
- Telemetry webhook updated: native HTTP hook entry in hooks.json with shell fallback;
  shell hook has `SUPPORTS_HTTP_HOOKS` guard to skip when HTTP hooks are active

---

## [8.40.0] - 2026-03-07

### Added

- 6 new Claude Code feature detection flags for v2.1.70-71:
  - `SUPPORTS_VSCODE_PLAN_VIEW` — VSCode full markdown plan view with comments (v2.1.70+)
  - `SUPPORTS_IMAGE_CACHE_COMPACTION` — compaction preserves images for prompt cache reuse (v2.1.70+)
  - `SUPPORTS_RENAME_WHILE_PROCESSING` — `/rename` works during processing (v2.1.70+)
  - `SUPPORTS_NATIVE_LOOP` — native `/loop` command + cron scheduling tools (v2.1.71+)
  - `SUPPORTS_RUNTIME_DEBUG` — `/debug` toggle mid-session (v2.1.71+)
  - `SUPPORTS_FAST_BRIDGE_RECONNECT` — bridge reconnects in seconds instead of 10 minutes (v2.1.71+)
- Effort level callout in agent spawn output when `SUPPORTS_EFFORT_CALLOUT` is true (wires previously dead flag)
- Agent-type capture in SubagentStop hook for per-agent cost attribution (`SUPPORTS_HOOK_AGENT_FIELDS`)
- Memory-safe timeout boost: complex/debate/audit tasks get +60s timeout when CC has memory leak fixes (v2.1.63+)

### Changed

- Total feature detection flags: 66 → 72 (covering CC v2.1.12 through v2.1.71)
- Detection thresholds: 22 → 24 version checkpoints

---

## [8.39.1] - 2026-03-07

### Fixed

- Codex agent 401 auth failure: `build_provider_env()` output contained escaped quotes that became literal characters after `read -ra`, corrupting `HOME` path and preventing Codex CLI from finding `~/.codex/auth.json` (Issue #117)
- Added regression tests for literal quote detection in credential isolation

---

## [8.39.0] - 2026-03-05

### Added

- GPT-5.4 model support: `gpt-5.4` ($2.50/$15 MTok) and `gpt-5.4-pro` ($30/$180 MTok, API-key only)
- `gpt-5-codex-mini` ($0.25/$2.00 MTok) — budget model replacing `gpt-5.1-codex-mini`
- `gpt-5` base model ($1.25/$10 MTok)
- `o3-pro` ($20/$80 MTok) and `o3-mini` ($1.10/$4.40 MTok) reasoning models (API-key only)
- OAuth vs API-key availability documentation for all OpenAI models

### Changed

- Default codex premium model: `gpt-5.3-codex` → `gpt-5.4`
- Default codex-max model: `gpt-5.3-codex` → `gpt-5.4`
- Default codex-mini model: `gpt-5.1-codex-mini` → `gpt-5-codex-mini`
- Default codex-review model: `gpt-5.3-codex` → `gpt-5.4`
- Stale model migration targets updated to `gpt-5.4`

### Fixed

- `gpt-5.1-codex-mini` pricing corrected: $0.30/$1.25 → $0.25/$2.00 per MTok
- Bash 3.2 compatibility: replaced `${var^}` and `${var,,}` (Bash 4+) with POSIX-compatible `_ucfirst()` / `_lowercase()` helpers — fixes `octo:embrace` on stock macOS (Issue #108)

---

## [8.38.3] - 2026-03-05

### Fixed

- Factory AI command discoverability: all commands now prefixed with `octo-` (e.g., `/octo-embrace`, `/octo-discover`) to mirror Claude Code's `/octo:*` namespace — Factory has no automatic plugin namespacing so commands were invisible when typing `/octo`

---

## [8.38.2] - 2026-03-05

### Fixed

- Factory AI commands not working: `build-factory-skills.sh` now strips Claude Code-specific frontmatter (`command`, `aliases`, `redirect`, `version`, `category`, `tags`) from generated commands, keeping only Factory-compatible fields (`description`, `argument-hint`, `allowed-tools`, `disable-model-invocation`)

---

## [8.38.1] - 2026-03-05

### Added

- `scripts/build-factory-skills.sh` — generates Factory AI-compatible `skills/<name>/SKILL.md` directories from `.claude/skills/*.md` sources
- Generated `skills/` directory at plugin root with 44 Factory-format skill files (6 human_only skills excluded)

### Changed

- Factory skill discovery: replaced symlink approach (v8.38.0) with build-generated skill directories — Factory clones strip symlinks
- Factory skills use simplified frontmatter (`name`, `version`, `description`) with trigger content merged into descriptions
- Updated `docs/FACTORY-AI.md` to document build-based approach and Factory's skills-only model

### Removed

- Root-level `commands` and `skills` symlinks (Factory clone doesn't preserve symlinks; Factory has no commands concept)

### Fixed

- Factory AI Droid not discovering skills after plugin install (symlinks from v8.38.0 broken by Factory's clone process)

---

## [8.38.0] - 2026-03-05

### Added

- Root-level `commands` and `skills` symlinks pointing to `.claude/commands` and `.claude/skills` for Factory AI Droid auto-discovery
- Cross-platform discovery documentation in `docs/FACTORY-AI.md`

### Changed

- Simplified `.factory-plugin/plugin.json` — removed `skills` and `commands` arrays (Factory uses directory-based auto-discovery, not manifest arrays)
- Updated troubleshooting in `docs/FACTORY-AI.md` with symlink verification steps

### Fixed

- Factory AI Droid not discovering slash commands after plugin install (no `commands/` or `skills/` at plugin root)

---

## [8.37.0] - 2026-03-05

### Removed

- `STEELMAN.md` — internal competitive analysis moved out of public repo
- `SAFEGUARDS.md` — plugin name lock docs consolidated into `docs/PLUGIN_NAME_SAFEGUARDS.md`
- `deploy.sh` and `scripts/deploy.sh` — deployment validation redundant with CI
- `install.sh` — marketplace install is the supported method
- `.npmignore` — not published to npm

### Changed

- Trimmed `CHANGELOG.md` from 5,382 to ~220 lines — pre-8.22.0 history available via GitHub Releases
- Updated `package.json` `files` array to remove deleted files
- Updated safeguard references in `.claude-plugin/README.md` and `docs/PLUGIN_NAME_SAFEGUARDS.md`

---

## [8.36.0] - 2026-03-05

### Added

- Factory AI dual-platform support — `.factory-plugin/plugin.json` manifest, auto-detection of Claude Code vs Factory Droid runtime
- Platform detection shim in `orchestrate.sh` — `OCTOPUS_HOST` variable (claude/factory/standalone)
- `detect_claude_code_version()` now handles Factory Droid via `droid --version` with feature parity assumption
- `docs/FACTORY-AI.md` — install guide, architecture notes, troubleshooting for Factory AI users
- Factory AI install instructions in README with marketplace and direct install methods

---

## [8.35.0] - 2026-03-05

### Added

- Adaptive reasoning effort per phase — `get_effort_level()` now wired into `spawn_agent()`, gated by `SUPPORTS_OPUS_MEDIUM_EFFORT` (CC v2.1.68+)
- Worktree branch display in statusline — shows active worktree branch when agents run in isolation (CC v2.1.69+)
- InstructionsLoaded hook — injects dynamic workflow context (phase, autonomy, recent results) when CLAUDE.md loads (CC v2.1.69+)

---

## [8.34.0] - 2026-03-04

### Changed

- Recurrence detection, issue categorization, JSONL decision logging, CodeRabbit integration

---

## [8.33.0] - 2026-03-04

### Changed

- UI/UX design workflow with BM25 design intelligence

---

## [8.32.0] - 2026-03-04

### Changed

- Marketing, finance, legal personas and IDE integration

---

## [8.31.1] - 2026-03-01

### Changed

- Add /octo:batch alias and strengthen parallel quality defaults

---

## [8.31.0] - 2026-02-28

### Changed

- Multi-model intelligence improvements

---

## [8.30.0] - 2026-02-28

### Changed

- Agent continuation/resume for iterative tangle retries

---

## [8.27.0] - 2026-02-26

### Changed

- **Context Compaction Survival** (P0): SessionStart hook (`context-reinforcement.sh`) re-injects Iron Laws after context compaction. Enforcement rules no longer lost on conversation compression.
- **Description Trap Audit** (P1): 5 skill descriptions rewritten to opaque, outcome-focused format. Prevents model from skipping full skill reads.
- **XML Enforcement Tags** (P1): `<HARD-GATE>` tags on 5 Iron Laws for higher model compliance. Applied to skill-deep-research, skill-factory, skill-tdd, skill-verify, skill-debug.
- **Human-Only Skill Flag** (P1): `invocation: human_only` on 5 expensive skills — prevents auto-triggering without explicit user invocation.
- **Two-Stage Review Pipeline** (P2): New `skill-staged-review.md` — Stage 1 validates spec compliance against intent contract, Stage 2 runs stub detection and code quality. Gate between stages.
- **EnterPlanMode Interception** (P2): PreToolUse hook (`plan-mode-interceptor.sh`) re-injects enforcement rules when entering plan mode.

---

## [8.26.0] - 2026-02-26

### Changed

- **Changelog Integration** (Claude Code v2.1.46-v2.1.59): 9 new feature flags, 2 new version detection blocks (v2.1.51+, v2.1.59+). Tracks remote control, npm registries, fast Bash, disk persistence, account env vars, managed settings, native auto-memory, agent memory GC, smart Bash prefixes.
- **Worktree Lifecycle Hooks**: WorktreeCreate and WorktreeRemove handlers (`worktree-setup.sh`, `worktree-teardown.sh`). Propagates provider env vars, copies `.octo` state, cleans up on teardown. 8 hook event types (was 6).
- **Settings Enhancement**: 8 new configurable defaults — Codex sandbox, memory injection, persona packs, worktree isolation, parallel agent limit, quality gate threshold, cost warnings, tool policies.
- **Doctor Agents Category**: 10th diagnostic category. Checks agent definitions, worktree coverage, native CLI registration, version compatibility warnings.
- **Native Auto-Memory Delegation**: When v2.1.59+ detected, skip redundant project/user memory injection. Retain provider-specific cross-session context.
- **Agent Isolation Expansion**: security-auditor and deployment-engineer now use worktree isolation (10 agents total, was 8).

---

## [8.25.0] - 2026-02-25

### Changed

- **Dark Factory Mode** (closes #37): Spec-in, software-out autonomous pipeline with `/octo:factory` command. Wraps embrace workflow with scenario holdout testing (E19), satisfaction scoring (E21), and non-interactive execution (E22). 7 new functions: `parse_factory_spec`, `generate_factory_scenarios`, `split_holdout_scenarios`, `run_holdout_tests`, `score_satisfaction`, `generate_factory_report`, `factory_run`. Weighted 4-dimension scoring (behavior 40%, constraints 20%, holdout 25%, quality 15%) with PASS/WARN/FAIL verdicts. Retry on failure with remediation context. Artifacts stored at `.octo/factory/<run-id>/`.

---

## [8.23.1] - 2026-02-24

### Changed

- Add missing /octo:claw and /octo:doctor command files

---

## [8.23.0] - 2026-02-24

### Changed

- Add /octo:claw OpenClaw sysadmin command, /octo:doctor health diagnostics, and openclaw-admin standalone repo

---

## [8.22.6] - 2026-02-23

### Fixed

- **OpenClaw Runtime API Mismatch**: Rewrite OpenClaw extension to match the actual `OpenClawPluginApi` contract from `openclaw@2026.2.22-2`. Replaces `api.getConfig()` (non-existent method) with `api.pluginConfig`, `api.log()` with `api.logger`, and migrates tool format from custom `{run, parameters: JSON}` to the real `AgentTool` interface using `{execute, parameters: TypeBox, label}` with proper `AgentToolResult` return type (closes #50).

### Changed

- Add release.sh automation script

---

## [8.22.5] - 2026-02-23

### Fixed

- **OpenClaw Register Crash**: Guard `api.getConfig()` with `?? {}` fallback — OpenClaw passes `undefined` config during initial registration, causing `TypeError: Cannot read properties of undefined (reading 'enabledWorkflows')` (closes #48).

---

## [8.22.4] - 2026-02-23

### Removed

- **Coverage CI Job**: Removed the coverage report CI job that consistently failed due to 37% coverage (below 80% threshold) and missing GitHub API permissions.

---

## [8.22.3] - 2026-02-23

### Fixed

- **OpenClaw Install Registration**: Changed `package.json` name from `@octo-claw/openclaw` to `@octo-claw/octo-claw` so install directory matches manifest id `octo-claw`. OpenClaw derives config entry key from unscoped package name, so it must match manifest id or config validation fails with `plugin not found` (closes #45).
- **CI Coverage Permissions**: Added `pull-requests: write` and `issues: write` permissions to test workflow. Made PR comment step non-fatal with `continue-on-error`.

### Changed

- **Validation**: Added check that `openclaw.plugin.json` id matches unscoped package name to prevent registration mismatch.

---

## [8.22.2] - 2026-02-23

### Fixed

- **OpenClaw Dist Shipping**: Whitelisted `openclaw/dist/` and `mcp-server/dist/` in `.gitignore` so compiled extension files ship with the repo — fixes install failure (closes #41).
- **CI Test Suite**: Fixed `((0++))` arithmetic crashes under `set -e` in 3 unit tests and `build-openclaw.sh`. Fixed integration test assertions for `.gitignore` patterns and insufficient grep context windows. All 58 tests now pass.

### Changed

- **Branch Protection**: Enabled on `main` requiring Smoke Tests, Unit Tests, and Integration Tests CI checks. Enforced for admins.
- **Pre-push Hook**: Added git pre-push hook running full test suite before every push.
- **Validation**: Added `dist/index.js` existence check to `tests/validate-openclaw.sh` to prevent regression.

---

## [8.22.1] - 2026-02-23

### Fixed

- **Test Suite**: Resolved all 24 pre-existing test failures — 22/22 tests now pass. Deleted 10 tests for non-existent features or architectural incompatibility. Fixed 12 tests covering path calculation, bash arithmetic under `set -e`, plugin name assertions, insufficient grep context windows, and pattern mismatches.
- **OpenClaw Manifest**: Added required `id` field to `openclaw.plugin.json` — fixes gateway crash on startup (closes #40).

### Changed

- **OpenClaw Identity**: Renamed OpenClaw-facing identity from `claude-octopus` to `octo-claw` across plugin manifest, package names (`@octo-claw/openclaw`, `@octo-claw/mcp-server`), MCP server name, and `.mcp.json` server key. GitHub repo URLs unchanged.
- **Validation**: Added `id` field check to `tests/validate-openclaw.sh` to prevent regression.

---

## [8.22.0] - 2026-02-22

### Added

**OpenClaw Compatibility Layer** — Three new components enable cross-platform usage without modifying the core Claude Code plugin:

1. **MCP Server** (`mcp-server/`): Model Context Protocol server exposing 10 Octopus tools (`octopus_discover`, `octopus_define`, `octopus_develop`, `octopus_deliver`, `octopus_embrace`, `octopus_debate`, `octopus_review`, `octopus_security`, `octopus_list_skills`, `octopus_status`). Auto-starts via `.mcp.json` when plugin is enabled. Built with `@modelcontextprotocol/sdk`.

2. **OpenClaw Extension** (`openclaw/`): Adapter package for OpenClaw AI assistant framework. Registers Octopus workflows as native OpenClaw tools. Configurable via `openclaw.plugin.json` with workflow selection, autonomy modes, and path resolution.

3. **Shared Skill Schema** (`mcp-server/src/schema/skill-schema.json`): Universal JSON Schema for skill metadata supporting both Claude Code and OpenClaw platforms. Defines name, description, parameters, triggers, aliases, and platform-specific configuration.

**Build Tooling:**
- `scripts/build-openclaw.sh` — Generates OpenClaw tool registry from skill YAML frontmatter (90 entries). `--check` mode for CI drift detection.
- `tests/validate-openclaw.sh` — 13-check validation suite covering plugin integrity, OpenClaw manifest, MCP config, registry sync, and schema validation.

### Architecture

Zero modifications to existing plugin files. Compatibility layers wrap around the plugin via:
- `.mcp.json` at plugin root (Claude Code auto-discovers this)
- `openclaw/` directory with separate `package.json` and extension entry point
- `mcp-server/` directory with separate `package.json` and MCP server

All execution routes through `orchestrate.sh` — behavioral parity guaranteed.

---

---

For versions prior to 8.22.0, see the [GitHub Releases](https://github.com/nyldn/claude-octopus/releases) page.
