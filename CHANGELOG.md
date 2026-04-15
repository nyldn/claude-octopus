## [9.22.0] - 2026-04-15

### Added

- **Memory provider contract** (`scripts/lib/memory.sh`) — unified façade over backends; callers use `memory_search`, `memory_observe`, `memory_context`, `memory_available` instead of touching bridges directly. Auto-detects `mcp-memory-service` via `mcpServers` config signature; falls back to `claude-mem`. Env overrides: `OCTOPUS_MEMORY_BACKEND`, `OCTOPUS_MEMORY_SCOPE`, `OCTOPUS_MEMORY_SEARCH_MERGE`. Detection never spawns `uvx` speculatively — avoids accidental Torch/CUDA pull. Closes discussion in #220.
- **Gemini in-band model fallback** (`scripts/helpers/gemini-exec.sh`) — on `404 / ModelNotFoundError`, retries with next entry in `OCTOPUS_GEMINI_FALLBACK_MODELS` (default: `gemini-2.5-flash`). Transient errors (429, 5xx) are not retried — stays in the circuit-breaker's lane. Stdin cached to tempfile so replay works across attempts.
- **Agent output cap** — `run_agent_sync` now truncates at `OCTOPUS_AGENT_MAX_OUTPUT_BYTES` (default 256 KiB, 0 disables). Tail-biased: preserves first 4 KiB + last ~252 KiB so Codex-style deliverable summaries (always at the end) survive. Banner reports original size.
- **Partial-writes diagnostic on timeout** — when `run_agent_sync` exits 124/143, `find -newermt` surfaces files written before SIGTERM so users know completed deliverables exist. GNU-only check skips silently on macOS BSD find.

### Fixed

- **`doctor smoke` silently aborting** — five converging defects: (1) `((var++))` under `set -eo pipefail` exits 1 when var=0 — changed to `((++var))`; (2) double `shift` in `orchestrate.sh` discarded the `smoke` category arg before it reached `do_doctor`; (3) Codex smoke test passed prompt as positional arg — codex 0.120.0 rejects it, now piped via stdin; (4) Gemini cold-start (~12–18s) exceeded hardcoded 10s smoke timeout — now `OCTOPUS_GEMINI_SMOKE_TIMEOUT` (default 30s); (5) `/tmp/octo-model-cache-*.json` could hold two concatenated JSON documents from a concurrent-write race — validated with `jq -cse`, discarded and rebuilt on corrupt payload.
- **Scheduler version hardcoded to `v8.16.0`** — 7 major versions stale. New `octopus_plugin_version()` in `lib/common.sh` reads from `.claude-plugin/plugin.json` at runtime (sed fallback if jq absent). `validate-release.sh` now warns when no git tag matches current version.

### Changed

- **session.sh** routes phase-completion observations through `memory_observe` instead of calling `claude-mem-bridge.sh` directly — existing claude-mem deployments unaffected; mcp-memory-service users get observations routed to their backend.
- **README** — update and clean-reinstall steps now include `marketplace update` / `marketplace remove` commands to prevent stale cached plugin versions.
- **CI**: bump `actions/github-script` v8 → v9.

---

## [9.21.0] - 2026-04-10

### Changed

- CC v2.1.89-101 sync — 15 new feature flags (137 total), PermissionDenied audit hook, session auto-titling, macOS CI matrix, BSD/GNU portability lint

---

## [9.20.3] - 2026-04-10

### Fixed

- **Doctor false failure on Windows/Git Bash** — `jq.exe` on Windows outputs CRLF line endings. In `doctor_check_hooks()`, the trailing `
` prevented quote-stripping from matching, leaving a stale `"` in hook script paths. The `-f` test then failed, reporting a false "Hook script missing" error. Fixed by piping jq output through `tr -d '
'` before path resolution. No impact on Unix. Closes #258.

## [9.20.2] - 2026-04-09

### Fixed

- **Broken symlinks in vendor skill** — `vendors/ui-ux-pro-max-skill` was a git submodule with 3 internal symlinks (`.shared/ui-ux-pro-max`, `.claude/skills/.../scripts`, `.claude/skills/.../data`). Claude Code's plugin installer doesn't recurse submodules, so these broke on install. Replaced the submodule with plain vendored files, resolving all symlinks to real copies. Fixes E2E B10 failure.

## [9.20.1] - 2026-04-09

### Fixed

- **`orchestrate.sh` not found by LLM Bash tool** — `${CLAUDE_PLUGIN_ROOT}` is only available in hook execution context, not in the LLM's Bash shell. All skill, command, persona, and OpenClaw files referenced this variable, causing multi-LLM dispatch to silently fall back to Claude-only. Replaced with `${HOME}/.claude-octopus/plugin/` across 104 files, with a stable symlink created by session-manager.sh at session start.
- **Shared template block** (`skills/blocks/provider-check.md`) also used `${CLAUDE_PLUGIN_ROOT}` with a broken `dirname` fallback — fixed at source so `gen-skill-docs.sh` propagates correctly.
- **Hardcoded provider metrics** — `update_metrics "provider" "codex/gemini/claude"` in flow templates replaced; metrics should track actual providers used, not assume a fixed set.
- **RTK install URL** contained upstream repo attribution (`rtk-ai`) in skill-doctor.md — replaced with generic cargo install target.
- **README command count** — "49 commands" corrected to 48.

### Changed

- **15 test suites fixed** — Removed 2 stale v8.x tests (testing deleted `get_agent_command` and non-existent `embrace.yaml`). Fixed skill-verify path lookup, hooks.json registration assertions for opt-in hooks, flow-develop self-regulation assertions, OpenClaw registry sync, skill count expectation (50→51), README badge/count checks.
- **CLAUDE.md** — Added Enforcement Best Practices section with Validation Gate Pattern documentation.
- **embrace.md** — Added answer incorporation instructions for intent questions.

## [9.20.0] - 2026-04-06

### Added

- **EXECUTION MECHANISM enforcement** — All 13 multi-LLM workflow commands now have explicit `NON-NEGOTIABLE` blocks prohibiting agents from substituting Claude-native tools for orchestrate.sh dispatch. Covers embrace, discover, define, develop, deliver, multi, review, security, debate, research, factory, staged-review, prd.
- **Embrace chains skill invocations** — `/octo:embrace` now invokes `/octo:discover` → `/octo:define` → `/octo:develop` → `/octo:deliver` as sequential Skill calls. Each phase loads fresh enforcement instructions, surviving context compaction in long sessions.
- **Post-compaction enforcement re-injection** — `post-compact.sh` now detects active multi-LLM workflows and re-injects execution enforcement text after compaction drops the original skill instructions.
- **Workflow verification hook** — New `workflow-verification.sh` (SessionEnd) detects when a multi-LLM workflow ran but produced no result files, warning that orchestrate.sh dispatch may not have executed.
- **Interactive `/octo:model-config` wizard** (v4.0) — No-args invocation now shows a dashboard + AskUserQuestion menu: provider defaults, phase routing, debate/multi-LLM participants, consensus threshold, cost mode, reset. CLI-style direct arguments still work.
- **Never-dismiss guardrails** — `/octo:setup` and `/octo:model-config` can no longer be silently dismissed for returning users. Both always show interactive UI.
- **New test suites** — `test-execution-mechanism.sh` (32 assertions), `test-interactive-commands.sh` (10 assertions) guard against enforcement regressions.

### Fixed

- **`/octo:embrace` not dispatching to external providers** — Agent displayed workflow banner but used only Claude-native tools (Agent, WebFetch) instead of calling orchestrate.sh. Root cause: missing explicit prohibition + context compaction dropping skill instructions in long sessions.
- **`/octo:setup` dismissing returning users** — Agent said "you're already set up" instead of showing interactive menu. Fixed with mandatory first-output-line and never-dismiss guardrails.

## [9.19.3] - 2026-04-04

### Added

- **First-run auto-setup** — SessionStart hook detects first install and auto-prompts `/octo:setup`. Marker file at `~/.claude-octopus/.setup-complete`.
- **Interactive `/octo:setup` wizard** — Rewritten with AskUserQuestion for provider install (Codex/Gemini/Copilot/Qwen), OAuth/API-key auth, RTK install + hook config, and work mode selection. Replaces passive instruction dump.

### Changed

- **`sys-configure` skill** — Now redirects to `/octo:setup` instead of duplicating setup logic. "configure", "config", and "setup" all route to the same interactive wizard.

---

## [9.19.2] - 2026-04-04

### Changed

- **`/octo:doctor` interactive remediation** — Doctor now uses AskUserQuestion to offer fixes for every fixable issue: RTK install (brew/cargo), RTK hook config, missing providers, expired auth, missing deps. Batches multiple issues into multiSelect prompts.
- **Token optimization report** — Doctor includes RTK status, hook config, compressor analytics, and octo-compress availability at the end of every run.

### Removed

- **`/octo:optimize` command** — Folded entirely into `/octo:doctor` which now handles both diagnostics and interactive remediation. 48 commands total (was 49).

### Fixed

- **Private VPS details** — Removed from `docs/DEVELOPER.md` (E2E infrastructure references).

---

## [9.19.1] - 2026-04-04

### Fixed

- **MCP server opt-in** — `octo-claw` MCP server no longer auto-registers in `.mcp.json`, preventing permanent `✘ failed` status in `/mcp` panel. Now requires `OCTO_CLAW_ENABLED=true` to start. (#240, thanks @everton-dgn)
- **MCP security hardening** — Blocked security-governing env vars (`OCTOPUS_SECURITY_V870`, `OCTOPUS_GEMINI_SANDBOX`, etc.) from being overridden via MCP client environment.
- **IDE editor context** — New `octopus_set_editor_context` MCP tool injects IDE state (file, selection, cursor) into orchestration. 50KB selection limit.
- **Self-regulation in develop loops** — WTF score tracking added to `flow-develop.md` for runaway iteration detection (hard cap: 50 iterations).

---

## [9.19.0] - 2026-04-04

### Added

- **Claude Code v2.1.87-92 sync** — 13 new `SUPPORTS_*` flags (122 total): PostCompact hook (v2.1.76+), Elicitation hooks (v2.1.76+), `--bare` flag (v2.1.87+), model capability env vars (v2.1.87+), console auth (v2.1.87+), worktree HTTP hooks (v2.1.87+), deep link 5K (v2.1.88+), session ID header (v2.1.89+), marketplace offline (v2.1.90+), plugin executables (v2.1.91+), MCP result size (v2.1.91+), disable skill shell (v2.1.91+), multiline deep links (v2.1.91+).
- **PostCompact context recovery** — New `post-compact.sh` hook reads workflow state snapshot saved by `pre-compact.sh` and re-injects phase/workflow/autonomy context after compaction. 10-minute staleness window.
- **Elicitation hooks** — `Elicitation` and `ElicitationResult` hook events log MCP structured input for observability.
- **Plugin CLI executable** — `bin/octopus` bare command (CC v2.1.91+ auto-discovers `bin/`). Subcommands: `doctor`, `version`, `session`, `fleet`.
- **Headroom-inspired token compression** — `hooks/output-compressor.sh` PostToolUse hook auto-detects large outputs (JSON arrays, logs, HTML, verbose text >3K chars) and injects compressed summaries. `bin/octo-compress` standalone CLI for pipe-based compression (`npm install 2>&1 | octo-compress`). HUD "Saved" column tracks cumulative savings.
- **Rate limit HUD fallback** — `octopus-hud.mjs` uses CC-provided `rate_limits` from stdin when OAuth API is unavailable (enterprise, API-billing, expired creds).
- **managed-settings.d fragment** — Deploys `octopus-defaults.json` (git instructions off, auto-memory dir) on session start. Atomic write with tmpfile+mv.
- **Token optimization command** (`/octo:optimize`) — RTK analysis, context usage, guided setup. 49 commands total.
- **RTK-aware context nudges** — RTK gain stats at WARNING+CRITICAL+AUTO_COMPACT severity levels.
- **HUD RTK column** — Cumulative tokens saved and average compression percentage.
- **20 new doctor tips** — PostCompact, bare flag, model caps, console auth, plugin executables, MCP result size, marketplace offline, disable skill shell, elicitation hooks, session ID header, deep link 5K, worktree HTTP hooks, multiline deep links, rate limit fallback, managed settings, output compressor, octo-compress CLI.
- **67-test suite** — `test-cc-v2184-91-sync.sh` covers all v9.19 flags, cascade blocks, hooks, executables, wiring, doctor tips, HUD fallback, orphan cleanup, hook consistency.

### Changed

- **Token savings (~7,300 tokens/session):**
  - Hook conditional `if` gates on 4 hooks (careful-check, freeze-check, telemetry, output-compressor) — skip process spawns when conditions aren't met
  - PostToolUse consolidation — single `post-tool-dispatch.sh` replaces 3 blanket hooks
  - Context-reinforcement trim — 750→150 tokens (compact gate names)
  - Lazy skill `paths:` on 9 specialized skills — only listed when relevant files present
  - CLAUDE.md diet — 3,800→2,418 tokens (dev sections moved to `docs/DEVELOPER.md`)
  - additionalContext minimization — `[🐙 Octopus]` → `[🐙]` across all hooks
- **`--bare` flag** — All `claude -p` subprocess calls use `--bare` on CC v2.1.87+ for faster synthesis (skips hooks/LSP/plugin sync).
- **Version cascade ordering** — Fixed v2.1.30 and v2.1.80 block inversions in `providers.sh`. Merged duplicate v2.1.33 blocks.
- **Hook consistency** — Added `set -euo pipefail` to `worktree-setup.sh`, `worktree-teardown.sh`, `config-change-handler.sh`, `telemetry-webhook.sh`.

### Fixed

- **HUD cache bypass** — Error-cached OAuth result no longer blocks CC-provided rate limit fallback for 15 seconds.
- **JSON heredoc injection** — `session-start-memory.sh` fallback path now uses `jq -n --arg` instead of raw variable expansion in heredoc.
- **Post-compact staleness** — Window raised from 5 to 10 minutes for large context compactions.

### Removed

- **`session-sync.sh`** — Orphaned hook (merged into `session-start-memory.sh`). Removed from `hook-profile.sh` allowlist.
- **`"executables"` manifest field** — Not a valid `plugin.json` schema field; CC auto-discovers `bin/` by convention.

---

## [9.18.1] - 2026-04-02

### Fixed

- **Embrace workflow silent exit** — `cleanup_old_results()` and `cleanup_cache()` in `semantic-cache.sh` used bare `[[ cond ]] && cmd` patterns that returned exit code 1 under `set -e` when no files needed cleaning. Added `|| true` to prevent premature script termination. (#241)
- **SESSION_FILE path expansion** — `SESSION_FILE` was derived from `WORKSPACE_DIR` at source-time in `quality.sh`, before `WORKSPACE_DIR` was defined in `orchestrate.sh`, causing it to expand to `/session.json`. Re-derived after `WORKSPACE_DIR` is set. (#241)

---

## [9.18.0] - 2026-03-31

### Added

- **Claude Code v2.1.84-87 sync** — 9 new `SUPPORTS_*` flags: skill effort frontmatter (v2.1.80+), rate limit statusline (v2.1.80+), TaskCreated hook (v2.1.84+), skill paths globs (v2.1.84+), plugin userConfig (v2.1.84+), conditional hook `if` field (v2.1.85+), PreToolUse AskUserQuestion answering (v2.1.85+), skill description 250 char cap (v2.1.86+), TaskOutput deprecation (v2.1.83+).
- **Skill `effort:` frontmatter** — 10 research/analysis skills set to `effort: high`, 7 quick/diagnostic skills set to `effort: low`. Saves tokens on light tasks, allocates more thinking on deep work. CC v2.1.80+ reads this automatically.
- **Skill `paths:` frontmatter** — 4 skills scoped to relevant file globs (TDD → test files, doc-sync → markdown, security-framing → env/auth files, coverage-audit → test/coverage dirs). CC v2.1.84+ auto-activates matching skills.
- **TaskCreated discipline hook** — When discipline mode is on, fires brainstorm gate reminder when tasks are created. Prevents jumping into implementation without a plan.
- **Marketplace sync counts from `.claude/commands/`** — Source of truth for command count (was counting Codex `commands/` dir which lagged).

### Fixed

- **Windows/Git Bash compatibility** — add `--skip-git-repo-check` to all Codex CLI dispatch commands; fix pipe chain stdout loss with MINGW-aware file-based capture fallback; add `WORKSPACE_DIR` fallback to smoke test and tier cache paths (#235)
- **Model resolver cross-provider routing** — routing phases targeting a different provider now skipped instead of contaminating model selection (#235)
- **Scope drift skill enforcement** — add MANDATORY COMPLIANCE block (#236)
- **Test: "Which Tentacle?" heading renamed** — matches "Pick a Command by Goal" heading.
- **test-codex-compat.sh** — skill count pattern updated to range.
- **OpenClaw registry sync** — `skill-verify` → `skill-verification-gate`, add `discipline` command.

---

## [9.17.0] - 2026-03-31

### Added

- **Discipline mode** (`/octo:discipline on`) — 8 auto-invoke gates enforced at SessionStart. 5 development gates (brainstorm, verification, review, response, investigation) + 3 knowledge work gates (context detection, structured decisions, intent locking). Off by default, persists across sessions. `/octo:quick` bypasses all gates.
- **Cursor IDE plugin support** — `.cursor-plugin/plugin.json` for Cursor marketplace compatibility.
- **OpenCode install guide** — `.opencode/INSTALL.md` with symlink-based skill discovery.
- **Codex CLI compatibility layer** — `scripts/build-codex-skills.sh` generates `.codex/skills/` from `.claude/skills/`, `OCTOPUS_HOST` detects codex/gemini hosts, graceful degradation for non-Claude hosts. 80-test suite.
- **Verification gate skill** — "Evidence before claims" iron law. Replaces and consolidates old `skill-verify`. Red-green regression examples.
- **Review response skill** — How to handle code review feedback. Verify before implementing, push back when wrong, never agree blindly.
- **Two-stage post-implementation review** — `flow-develop` now runs spec compliance check first, code quality review second, E2E verification third — all in parallel.
- **Comparison table** — Claude Code vs Superpowers vs Octopus in collapsible README section.
- **Built with Claude badge** + CI status badge + test count badge in README.
- **GitHub Discussions enabled** — pinned "Start Here" post with FAQ.
- 3 good-first-issue tickets created (#221, #222, #223).

### Changed

- **README opening rewritten** — leads with the problem (blind spots) and the benefit (they surface before you ship), not a feature list.
- **README headings renamed** — benefit-first titles (e.g., "Top 8 Tentacles" → "8 Commands That Matter Most", "Reaction Engine" → "Built-in Reaction Engine").
- **Root directory streamlined** — 25 → 19 visible items. Moved CODE_OF_CONDUCT, CONTRIBUTING, PRIVACY to `docs/`, templates to `config/templates/`, workflows to `config/workflows/`, assets to `docs/assets/`.
- **Marketplace description** — benefit-driven copy instead of version-note changelog summary.
- **`.claude-plugin/README.md` rewritten** — 27-line internal dev note → 65-line user-facing landing page with before/after example, quickstart, common jobs table.
- **Star history chart** moved from mid-page to bottom of README.
- **What's New v9 row** updated with circuit breakers, loop self-regulation, HUD, cache-aligned prompts.

### Fixed

- **Marketplace sync** — `sync-marketplace.sh` now counts skills from `.claude/skills/` (source of truth, 51) instead of `skills/*/SKILL.md` (Codex copies, 45).
- **CI green** — docs-sync test matches renamed headings + emoji prefix, plugin expert review accepts `docs/assets/`, empty `Stop: []` hook array removed.
- **Hooks.json** — removed empty Stop array that caused validation failure in E2E runner.

### Removed

- **PostHog telemetry** — unreliable hook delivery (CLAUDE_PLUGIN_ROOT not always set, events only flush on SessionEnd). PRIVACY.md already stated "no telemetry" — now that's actually true.
- **`skill-verify`** — consolidated into `skill-verification-gate` (examples preserved, multi-provider context added).

---

## [9.16.0] - 2026-03-29

### Skill Enhancements

- **Sentinel canary monitoring** — `/octo:sentinel` auto-detects deployments and runs post-deploy health checks: HTTP status, load time regression (flagged at >50% baseline), console error detection, and Core Web Vitals comparison. Auto-triggers after `/octo:deliver` completes — no manual flags needed.
- **Security auto-escalation** — `/octo:security` now auto-detects Quick vs Deep mode from the git diff. Touching auth, security, CI/CD, or dependency files auto-escalates to Deep mode with secrets archaeology (git history scan for leaked credentials), CI/CD pipeline audit (GitHub Actions injection risks), skill supply chain verification, and STRIDE threat modeling.
- **Design shotgun** — `/octo:design-ui-ux` auto-dispatches to 3+ providers for parallel design variant generation when enough providers are available. Each provider produces an independent style direction; results presented as a side-by-side comparison board. Falls back to standard single-direction mode with fewer providers.
- **Ship pipeline** — `skill-finish-branch` now always runs a multi-provider diff review before shipping (no size threshold). Adds optional version bump (patch/minor/major) and auto-generated changelog entries from commit history.
- **Scope drift detection** — New `skill-scope-drift` compares diff against stated intent (TODOS.md, PR body, commit messages) and flags scope creep or missing requirements. Auto-integrated into `/octo:review` Step 1b — informational only, never blocks.
- **Dynamic fleet dispatch** — `build-fleet.sh` enforces model family diversity across agents. Providers are spread across OpenAI, Google, Microsoft, Alibaba, and Anthropic families to avoid agreement bias from same-family models.

### Terminal UX

- **Statusline identity fix** — Tier 3 statusline now shows `[🐙 Octopus]` instead of `[🐙 Claude]`. Tier 2 idle mode shows `[🐙 Octopus]` instead of just `[🐙]`.
- **Standardized hook prefixes** — All hook `additionalContext` messages now use `[🐙 Octopus]` prefix. Previously varied: `[Octopus Context Monitor]`, `[Compound Task]`, `[Octopus Strategy Rotation]`.
- **Consolidated provider check** — New `scripts/helpers/check-providers.sh` replaces 7 inline copies of the 8-line provider check block across skill files.
- **Output helpers** — New `octopus_header()`, `octopus_separator()`, `octopus_phase_banner()`, `octopus_complete()` in `lib/common.sh` standardize box-drawing output. Phase banners, config display, and error boxes all use consistent 60-char width.
- **Compact banner mode** — Set `OCTOPUS_COMPACT_BANNERS=true` for single-line activation banners instead of full provider blocks.
- **Clear action descriptions** — Replaced whimsical tentacle messages ("Extending empathy tentacles...") with clear provider dispatch descriptions across 6 files.
- **Consistent completion messages** — All workflow completion messages now use `octopus_complete()` helper: `✓ [Workflow] complete`.

### Other

- **Codex compatibility layer** — Host platform detection for Codex and Gemini runtimes with graceful degradation.
- **PostHog telemetry removed** — Unreliable hook delivery; telemetry hooks removed.
- **README polish** — Hero demo GIF, Built with Claude badge, streamlined comparison table.

---

## [9.15.2] - 2026-03-27

### Fixed

- **Silent error swallowing in provider dispatch** — Added `set -o pipefail` to spawn_agent subshell. Pipeline `printf | codex | tee` was reporting tee's exit code (always 0), silently hiding Codex/Gemini failures.
- **Codex explicit stdin flag** — All `codex exec` commands now include `-` for explicit stdin reading instead of relying on auto-detection.
- **Gemini stdout noise filter** — MCP status messages, extension loading, and keychain fallback messages no longer pollute results.
- **Windows PATH space-splitting** — `build_provider_env()` skips `env -i` credential isolation on Windows (MINGW/MSYS/CYGWIN) where `C:\Program Files` paths break word-splitting.
- **Error classification expanded** — `classify_error()` now handles permission-denied, module-not-found, and MCP-issues patterns for proper circuit breaker response.
- **MANDATORY COMPLIANCE** added to 9 commands/skills (factory, prd, sentinel, resume, schedule, code-review, parallel-agents, debug, writing-plans).
- **PostHog telemetry** reads key from settings.json when env var unset.
- **Codex review dispatch** — Strengthened JSON output format requirement to prevent unstructured diff dumps.
- **MANDATORY COMPLIANCE audit test** — New `test-mandatory-compliance.sh` (38 tests) catches missing enforcement automatically.

---

## [9.15.1] - 2026-03-27

### Fixed

- **dispatch.sh Codex `--full-auto` flag** — All four `codex exec` variants in `get_agent_command()` now include `--full-auto`, preventing hangs in non-interactive execution (debate, sync dispatch, spawn). (#212, #213)
- **doctor hook validation false positives** — Hook script path parser now handles `bash`-wrapped commands and env-var prefixed commands (`KEY=value script.sh`), eliminating 5 false failures in `/octo:doctor` hooks check. (#214)
- **MCP server zod compatibility** — Bumped `zod` from 3.24.1 to 3.25.67 in `mcp-server/package.json` to resolve `ERR_PACKAGE_PATH_NOT_EXPORTED` on `zod/v4` subpath required by `@modelcontextprotocol/sdk` 1.26.0. (#215)

## [9.15.0] - 2026-03-26

### Added

- **RTK companion detection** — `/octo:setup` and `/octo:doctor` now detect RTK (Rust Token Killer) and recommend it for 60-90% bash output compression. Context-awareness hook suggests RTK at WARNING level when not installed. Fully optional — no hard dependency.
- **Cache-aligned prompt construction** — Restructured `spawn_agent()` and `run_agent_sync()` to place stable content (persona, skills, boilerplate) before variable content (timestamps, session state, provider history). Enables Claude's 90% cached-token discount on repeated prompt prefixes.
- **Anomaly-preserving output truncation** — `guard_output()` now preserves error/failure lines (ERROR, FATAL, FAIL, PANIC, Traceback, Exception, CRITICAL) when truncating large outputs. Shows head + anomalous lines with line numbers + tail instead of blind truncation. Falls back to original behavior when no anomalies found.
- 3 new test suites: `test-rtk-detection.sh` (17), `test-cache-alignment.sh` (29), `test-anomaly-truncation.sh` (20). 132/132 tests passing.

### Fixed

- **test-v8.5.0 Agent Teams grep window** — Widened `grep -A 400` to `-A 500` for spawn_agent function growth from cache-alignment restructuring.

---

## [9.14.1] - 2026-03-26

### Added

- **Loop self-regulation** — Configurable weights for WTF-likelihood scoring and sliding-window stuck detection. Users can override defaults (revert penalty, unrelated-files penalty, threshold, hard cap, window size) via `~/.claude-octopus/loop-config.conf`.
- **Self-regulation wired into flow-develop** — Iterative development cycles now track WTF score and pattern detection, preventing runaway implementation loops.
- **Self-regulation wired into skill-debug** — Debug fix loops now track WTF score alongside the existing 3-strike rule, adding quantitative drift detection to fix attempts.
- 13 new tests for configurable weights, flow-develop wiring, and skill-debug wiring (33 total in test-loop-self-regulation.sh).

---

## [9.14.0] - 2026-03-26

### Added

- **Provider Reliability Layer (CONSOLIDATED-01)** — Circuit breaker state persists across sessions in `provider-state/` (via `CLAUDE_PLUGIN_DATA` or `~/.claude-octopus/`). `spawn_agent()` checks `is_provider_available()` before dispatch, records success/failure to circuit, classifies errors as transient/permanent via `classify_error()`. Transient errors (429, 500, timeouts) trigger graduated backoff; permanent errors (401, billing) open circuit immediately. Half-open probe after cooldown enables automatic recovery.
- **Doctor circuit breaker status** — `/octo:doctor` now shows open circuit breakers and provider health.
- **Bash 3.2 compatibility fix** — `classify_error()` no longer uses `${var,,}` (bash 4+ only).

---

## [9.13.0] - 2026-03-25

### Added

- **CC v2.1.78-83 feature detection** — 8 new `SUPPORTS_*` flags: StopFailure hook, PLUGIN_DATA dir, agent effort/maxTurns/disallowedTools, CwdChanged/FileChanged hooks, managed-settings.d, env scrub, initialPrompt.
- **CLAUDE_PLUGIN_DATA workspace** — `WORKSPACE_DIR` now prefers `${CLAUDE_PLUGIN_DATA}` when available (CC v2.1.78+), with backward-compatible fallback to `~/.claude-octopus/`.
- **Agent `effort` + `maxTurns` frontmatter** — All 32 agents configured: research agents `effort: high` / `maxTurns: 25`, balanced agents `effort: medium` / `maxTurns: 20`, lightweight agents `maxTurns: 15`.
- **Agent `initialPrompt`** — 4 key agents auto-submit first turn: code-reviewer, security-auditor, debugger, performance-engineer.
- **CwdChanged hook** — `hooks/cwd-changed.sh` re-detects project context (language, framework) on directory change.
- **StopFailure hook** — `hooks/stop-failure-log.sh` logs API errors to `error-log.jsonl` for diagnostics.
- **Agent Teams bridge: task dependencies** — `bridge_register_task()` accepts `depends_on` parameter; `bridge_is_task_unblocked()` blocks claiming until dependencies complete.
- **Agent Teams bridge: shutdown protocol** — `bridge_shutdown_teammate()` marks tasks as `shutting_down`; `bridge_cleanup()` warns about running tasks before archiving.
- **Agent Teams bridge: nested guard** — `bridge_init_ledger()` refuses to create a new team when an active workflow is running.
- **Agent Teams bridge: native discovery** — `bridge_discover_native_team()` reads CC's official `~/.claude/teams/` config.
- **Agent Teams enable check** — `bridge_is_enabled()` logs when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is not set; doctor tip suggests enabling it.
- **PostHog usage analytics** — `hooks/telemetry-posthog.sh` sends anonymous, opt-in session/workflow/error events to PostHog. Random UUID identity, PII scrubbing, local buffering with batch flush on SessionEnd. Project key embedded in `settings.json` — users disable with `POSTHOG_OPT_OUT=1`.
- 4 new test suites: `test-cc-v2183-sync.sh` (39), `test-shell-safe-hooks-v2183.sh` (8), `test-agent-teams-bridge.sh` (27), `test-posthog-telemetry.sh` (20).

### Fixed

- **128/128 tests passing** (was 105/128) — 18 test files updated to search `ALL_SRC` (orchestrate.sh + lib/*.sh) after v9.12.0 decomposition. Fixed NODE_NO_WARNINGS grep pattern, get_agent_command_array reference, YAML quoting, grep regex syntax, statusline fallback test, HTTP hook test.
- **Provider detection enforcement** — Added `PROVIDER_CHECK_START` bash snippet to `skill-debate.md`, `flow-parallel.md`, `skill-ui-ux-design.md` (were showing hallucinated banners).
- **Marketplace metadata version test** — `test-version-consistency.sh` now cross-checks both `metadata.version` fields to catch desyncs like the v9.10.3 incident.

### Changed

- **orchestrate.sh decomposition wave 2** — Moved 27 functions to lib/ modules. New lib/completions.sh. orchestrate.sh: 4,944 → 3,707 lines (-25%), 70 → 41 functions (-41%).
- **Dead code removal** — Removed `OLD_init_interactive_impl()`, `get_fallback_agent_v2()` (272 lines from interactive.sh).
- **Fork reduction** — Converted 28 `echo|tr/cut/wc` patterns to bash builtins. Fixed `cat|head` → `head` in factory-spec.sh.
- **Provider check template block** — Extracted snippet to `skills/blocks/provider-check.md`. Flow templates use `{{PROVIDER_CHECK}}` placeholder.

---

## [9.11.0] - 2026-03-23

### Changed

- OpenCode CLI provider — multi-provider router integration

---

## [9.10.3] - 2026-03-23

### Added

- **HUD: tool activity tracking** — Statusline shows active tools and counts (`◐ Edit: auth.ts │ ✓ Read ×3 │ ✓ Grep ×2`). Tracks Read, Write, Edit, Bash, Grep, Glob, WebSearch, WebFetch from transcript.
- **HUD: enhanced todo progress** — Shows active task text, not just count (`▸ Fix auth bug (2/5)`).
- **HUD: named presets** — `{"preset": "developer"}` in `.hud-config.jsonc`. Built-in: minimal, developer, full, performance. Preset indicator in Octo column.
- **PRIVACY.md** — Privacy policy for official Anthropic marketplace submission.
- **Cowork compatibility** — Added homepage field, updated keywords with "cowork", "multi-llm", all 8 provider names. Plugin was already format-compatible.

### Fixed

- **Smart router missing multi-LLM route** — `/octo:multi` was unreachable via `/octo:auto`. Keywords "multi", "multi-llm", "multi-provider" now route to `octo:multi`.
- **sync-marketplace.sh duplicate text** — "Run /octo:setup." appeared twice in marketplace description.
- **test-skill-templates.sh** — Updated for removed `skills/blocks/` directory.
- **Build artifacts** — Regenerated Factory skills, OpenClaw dist, new command wrappers.
- **Hardened plugin validation** (PR #208) — Factory YAML frontmatter normalization, `claude plugin validate` in release workflow.

---

## [9.10.2] - 2026-03-22

### Changed

- **embrace.sh dispatch** — Now detects all 5 CLI providers (codex, gemini, copilot, qwen, ollama) and dynamically builds dispatch strategies. 3+ available CLIs → all join the fleet. Qwen and Ollama now participate in research, review, and architecture workflows.
- **Debate participants** — Copilot (🟢) and Qwen (🟤) join as supplementary participants when available, alongside core four (Codex/Gemini/Sonnet/Opus).
- **Smart setup prompt** — Detects when legacy users have new providers (Copilot/Qwen/Ollama) and proactively informs them of extra tentacles.
- **Codex mini model** — Updated `gpt-5-codex-mini` → `gpt-5.4-mini` across dispatch, models catalog, provider routing, and docs. GPT-5.4 Mini is 2x faster and uses 30% token quota vs GPT-5.4.

### Fixed

- **Emoji conflict** — Qwen 🟠→🟤 (Sonnet keeps 🟠 as established).

---

## [9.10.1] - 2026-03-22

### Changed

- **SEO: "Multi-LLM orchestration" in opening paragraph** — First sentence now leads with "Multi-LLM orchestration plugin for Claude Code" and names all 8 providers. This is the Google snippet zone (~155 chars). Repo description updated to match.
- **README: outcome-first opening bullets** — Lead with what it does for you, not which 8 providers it uses. Defined jargon inline (personas = role-specific agents, skills = reusable workflows).
- **README: condensed What's New** — 14 detailed changelog rows → 3-row table by major version (v9/v8/v7) with best end-user features.
- **README: simplified Quickstart** — 3 commands upfront, alternatives + troubleshooting in collapsible `<details>` blocks.

---

## [9.10.0] - 2026-03-22

### Added

- **Qwen CLI as 8th provider**: Free-tier research via Qwen OAuth (1,000-2,000 requests/day). Fork of Gemini CLI — same dispatch pattern. Agent types: `qwen`, `qwen-research`. Detection, doctor, health check, dispatch, model resolver, circuit breaker, workflows, preflight, and install-deps all wired.
- **Copilot Coding Agent native files**: `.github/agents/*.agent.md` for all 10 agents. YAML frontmatter with Copilot tool aliases (read, edit, execute, search). Makes agents discoverable by GitHub's server-side coding agent.
- **Gemini .toml custom commands**: `.gemini/commands/octo/` with 4 persona commands (research, review, architect, implement) for human interactive use. Not used in headless dispatch (stdin+slash don't compose — verified via Codex source analysis).
- **Gemini provider test suite**: 44 tests covering dispatch, detection, doctor, health, models, circuit breaker, workflows, embrace, MCP, .toml commands, pricing, and config.

### Fixed

- **P0: json_extract reliability** — Replaced brittle regex (`"field":"value"`) with 3-tier fallback: jq (if available) → python3 one-liner → improved regex that handles whitespace, escaped quotes, numeric values, and missing fields.
- **P1: OpenRouter hardening** — Added `--max-time 60` timeout, HTTP status code handling (429 retry with Retry-After, 502/503/524 error messages), deduplicated `openrouter_execute()` and `openrouter_execute_model()` into one core function.
- **P1: DeepSeek model update** — `deepseek/deepseek-r1` → `deepseek/deepseek-r1-0528` across dispatch, model-resolver, models catalog, and docs.
- **CC version detection tests consolidated** — 4 test files merged into `test-cc-version-detection.sh` (103 tests).

---

## [9.9.3] - 2026-03-22

### Fixed

- **Copilot dispatch broken end-to-end** (#206, PR #207 by @PavelPancocha): 5 bugs that prevented Copilot from ever running in workflows despite detection:
  1. `dispatch.sh` returned bash function name (`copilot_execute`) instead of executable — `timeout` can't exec functions. Fixed: `copilot --no-ask-user`.
  2. `validate_agent_command()` in utils.sh rejected `copilot` — not in allowlist. Fixed: added `copilot` pattern.
  3. `embrace.sh` never included Copilot in dispatch strategies — only checked codex/gemini. Fixed: added `has_copilot` detection + 3/4-provider strategies.
  4. Headless `-p ""` stdin flag only appended for `gemini*` agents — Copilot needs it too. Fixed: extended condition to `copilot*`.
  5. Provider metrics tracking fell through to wildcard for copilot/ollama. Fixed: added explicit cases.
- **Stray `}` at EOF in workflows.sh** — caused syntax error when sourced (CodeRabbit catch from PR #207).
- **Codex smoke test timeout too short** — hardcoded 10s, but MCP initialization takes 20-40s. Now configurable via `OCTOPUS_CODEX_SMOKE_TIMEOUT` (default: 45s).

### Changed

- **README tagline** — "turns one model into three" → "orchestrates seven AI providers"
- **SECURITY.md** — supported versions 4.x → 9.x, fixed package names, added Copilot/Ollama to deps
- **CONTRIBUTING.md** — removed dead Python/coordinator.py refs, added real test commands, bash 3.x compat
- **PR template** — removed dead `coordinator.py` check, added real test/registry/version-bump checklist
- **Issue templates** — upgraded from markdown to YAML forms with provider dropdowns and version fields

### Added

- **CODE_OF_CONDUCT.md** — Contributor Covenant v2.1
- **Repo topics** — 12 discoverable tags (claude-code, multi-ai, ai-orchestration, etc.)

### Removed

- **39 stale remote branches** — all merged/orphaned branches cleaned up
- **Wiki and Projects tabs** — disabled (unused)
- **Discussions** — disabled

---

## [9.9.2] - 2026-03-22

### Changed

- **Documentation consolidation**: Removed 9 stale/redundant docs from plugin (archived to dev repo). Kept 7 user-facing docs + 5 provider configs. Rewrote `docs/README.md` index.
- **Provider counts normalized to 7** across README.md ("Seven Providers"), ARCHITECTURE.md (Copilot no longer "aspirational"), CLAUDE.md (detection section, modular config tree), COMMAND-REFERENCE.md ("47 commands"), copilot-instructions.md.
- **Debate references updated to four-way** across COMMAND-REFERENCE.md (was "3-way").

### Added

- **`config/providers/copilot/CLAUDE.md`**: New provider config file for GitHub Copilot CLI (was missing).

### Removed

- `docs/CLI-REFERENCE.md` — CLI flags are in orchestrate.sh `--help`
- `docs/PLUGIN-ARCHITECTURE.md` — Overlapped ARCHITECTURE.md, perpetually stale
- `docs/FACTORY-AI.md` — Factory-specific, stale counts
- `docs/SANDBOX-CONFIGURATION.md` — Documented invalid mode (`danger-full-access`); valid modes are in dispatch.sh
- `docs/NATIVE-INTEGRATION.md` — Outdated v8.15 content
- `docs/INTERACTIVE_QUESTIONS_GUIDE.md` — Developer reference, rarely used
- `docs/PDF_PAGE_SELECTION.md` — Belongs in document-skills plugin
- `docs/RELEASE_AUTOMATION.md` — Internal workflow, moved to dev repo
- `docs/agent-decision-tree.md` — Internal design doc, moved to dev repo

### Fixed

- **Ollama CLAUDE.md**: Corrected false "no streaming in CLI mode" claim.
- **AGENTS.md**: Fixed path `agents/` → `.claude/agents/`.

---

## [9.9.1] - 2026-03-22

### Fixed

- **Ollama dispatch missing**: Added `ollama|ollama-*` case to `dispatch.sh` and `ollama` to `AVAILABLE_AGENTS` — v9.9.0 wired detection but missed the dispatch branch.
- **detect-providers incomplete**: `detect_providers()`, `cmd_detect_providers()`, `install-deps.sh`, and `is_agent_available_v2()` now include Perplexity, Ollama, and Copilot (were only in doctor.sh).
- **copilot-instructions.md wrong path**: `marketplace.json` → `.claude-plugin/marketplace.json`.

### Changed

- **Removed inline adversarial steps**: Deleted STEP 6.5 (flow-define), STEP 3.5 (flow-develop), STEP 4.5 (flow-deliver) — superseded by centralized multi-LLM adversarial debate system (v9.4.0+v9.8.0).

---

## [9.9.0] - 2026-03-22

### Added

- **GitHub Copilot CLI as runtime provider** (#198): Official `copilot -p` programmatic mode (GA Feb 2026) with 5-tier fallback auth chain: `COPILOT_GITHUB_TOKEN` → `GH_TOKEN` → `GITHUB_TOKEN` → keychain → `gh` CLI. Agent types: `copilot`, `copilot-research`. Zero additional cost (uses GitHub Copilot subscription). Graceful degradation when unavailable.
- **Ollama as local LLM provider**: Primary integration via `ollama run` CLI dispatch. Doctor checks CLI install + server health + model count. Added to provider health checks, circuit breaker, and model resolver (`ollama*` → `llama3.3`). Secondary `ANTHROPIC_BASE_URL` bridge path documented for drop-in compatibility.
- **Repo-level agent discovery files**: `AGENTS.md` for GitHub Copilot coding agent discovery, `.github/copilot-instructions.md` for Copilot-specific repo instructions.
- **Adapter integration tests** (`test-adapter-flags.sh`): 23 tests covering debate flag placement, quality_threshold forwarding, env var allowlists, and Copilot wiring.

### Fixed

- **Debate flag placement in MCP/OpenClaw** (CRITICAL): Both adapters placed grapple-specific flags (`-r`, `--mode`) before the command, where orchestrate.sh's global parser consumed them incorrectly. OpenClaw's `-d` flag collided with the global `--dir` flag. Added `postFlags` parameter to both `runOrchestrate()` and `executeOrchestrate()`. Debate flags now correctly go after the subcommand.
- **`quality_threshold` silently ignored**: Both MCP and OpenClaw accepted the parameter but never forwarded it. Now passes `-q` flag to orchestrate.sh when non-default.
- **MCP/OpenClaw env var allowlists**: Added `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` (Ollama bridge), `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN` (Copilot auth), `PERPLEXITY_API_KEY` (was missing from OpenClaw).
- **OpenClaw registry stale**: Regenerated to 97 entries matching current skills/commands.
- **OpenClaw debate description**: "Three-way" → "Four-way" (Sonnet was added as 4th participant in v9.4.0).
- **OpenClaw debate style param**: Removed broken `style` param (no CLI mapping) and `-d` flag. Replaced with `mode` param (cross-critique/blinded) matching orchestrate.sh's actual `--mode` flag.
- **`test-openclaw-compat.sh` early abort**: `test_build_check_mode` and `test_validate_script_passes` used command substitution under `set -e`, causing the entire suite to abort on first failure. Fixed with `&& exit_code=0 || exit_code=$?` pattern.

### Changed

- **ARCHITECTURE.md**: Updated from "three providers" to 5 core + 2 optional (Codex, Gemini, Claude, Perplexity, OpenRouter + Ollama, Copilot). Updated provider table and ASCII diagram.
- **skill-copilot-provider.md v2.0**: Rewritten from `gh copilot` (retired) to official `copilot -p` programmatic mode. Documents auth chain, PAT setup, and premium request quota.
- **setup.md**: Added Copilot CLI setup section with install and auth instructions.
- **skill-doctor.md**: Updated providers table to match actual doctor checks.
- **test-copilot-provider.sh**: Updated assertions for v2.0 skill content (37 tests).

---

## [9.8.0] - 2026-03-22

### Added

- **Adversarial debate in 9 workflows**: Multi-LLM cross-checking now wired into `/octo:multi` (mandatory synthesis with disagreement surfacing), `/octo:spec` (completeness challenge), `/octo:define` (requirements challenge), `/octo:factory` (pre-embrace scenario coverage gate), `/octo:develop` (pre-implementation devil's advocate), `/octo:prd` (draft adversarial review), `/octo:staged-review` (multi-LLM Stage 2 with Codex logic + Gemini security), `/octo:parallel` (WBS decomposition cross-check), `/octo:tdd` (test design review). All skippable with `--fast`.
- **Visual activation indicators on all commands**: Every `/octo:*` command now shows a 🐙 indicator line when activated. 19 commands and 10 skills that were missing indicators now have them. 7 skills that falsely claimed `visual_indicators_displayed` in their contract now actually display one. 4 existing banners missing the 🐙 emoji prefix now include it.

### Fixed

- **test-debate-skill.sh CI failure**: Wrong helper path (`tests/smoke/test-helpers.sh` → `tests/helpers/test-framework.sh`) caused "Missing test-helpers.sh" on every CI run.
- **test-packaging-integrity.sh CI failure**: `set -euo pipefail` + `eval "source ..."` subshell broke on CI when sourced scripts referenced unset runtime variables. Replaced with file-existence check that doesn't require executing sourced code.

---

## [9.7.8] - 2026-03-21

### Fixed

- **Windows `${USER}` unbound variable crash** (#201): `$USER` is unset on Windows (Git Bash) — Windows uses `$USERNAME` instead. All 6 occurrences in the model cache path now use `${USER:-${USERNAME:-unknown}}` to handle both platforms.
- **Codex smoke test false negative outside git repos** (#202): `codex exec` requires a git repository, so the smoke test always failed with "Not inside a trusted directory" when run from a non-git directory. Now creates a temp git repo for the test and cleans up after. Added `GIT_REPO_REQUIRED` error classifier for a clearer message if the workaround fails.

---

## [9.7.7] - 2026-03-20

### Fixed

- **Broken Skill() dispatch in 9 commands**: `doctor`, `claw`, `loop`, `debug`, `deck`, `docs`, `security`, `staged-review`, `tdd` all used `Skill(skill: "skill-name")` which failed with "Unknown skill" because the Skill tool requires plugin-qualified names. Replaced with direct file read instructions. Net -93 lines.
- **Factory AI manifest stale at v8.41.0**: Bumped `.factory-plugin/plugin.json` to 9.7.7 with correct command/skill counts.
- **HTTP webhook hook no-op**: Removed the `type: http` hook entry that fired with an empty `OCTOPUS_WEBHOOK_URL`. The shell script fallback (`telemetry-webhook.sh`) already has the guard.
- **MCP server Node version guard**: Added `check-node-version.js` that fails fast with a clear error on Node < 18 instead of silently crashing.

### Changed

- **PostToolUse context-awareness scoped**: Changed from blanket `{}` matcher to `Bash|Agent|Write|Edit` only. Eliminates a bash process spawn on every Read/Grep/Glob call.
- **SessionStart hooks consolidated (5 → 4)**: Merged `session-sync.sh` into `session-start-memory.sh`, reducing process spawns per session start/resume/compact.
- **context-awareness.sh timeout guard**: Added `timeout 3 cat` pattern for stdin drain consistency with other hooks.

---

## [9.7.6] - 2026-03-19

### Added

- **Dependency installer** (`scripts/install-deps.sh`): New `check` and `install` modes that auto-detect and install missing CLIs (Codex, Gemini), jq, and the statusline resolver. Reports recommended plugin status (claude-mem, document-skills) with copy-paste `/plugin install` commands.
- **Setup dependency check**: `/octo:setup` now runs `install-deps.sh check` first — shows what's missing before provider detection. Offers `install` to fix everything in one shot.
- **Doctor deps category**: `/octo:doctor` gains a `deps` check category and install step (Step 3) for fixing missing software dependencies.

---

## [9.7.5] - 2026-03-19

### Fixed

- **Statusline version goes stale on plugin update**: `settings.json` contained a versioned cache path (e.g., `.../octo/9.6.1/hooks/...`) that never updated when the plugin upgraded. Added `statusline-resolver.sh` — a version-agnostic wrapper that finds the latest cached version via `sort -V`. New `statusline-auto-repair.sh` SessionStart hook auto-installs the resolver to `~/.claude-octopus/statusline.sh` and patches `settings.json` if it detects a stale versioned path.

---

## [9.7.4] - 2026-03-19

### Changed

- **3-tier adaptive statusline**: Tier 1 (Node 16+ HUD with smart columns), Tier 2 (bash + jq with context bar/cost/phase), Tier 3 (pure bash with grep/cut — zero external dependencies). Works on any POSIX system regardless of installed tools.
- **Node version check**: Verifies Node >= 16 before attempting ESM HUD delegation. Node 14-15 users gracefully fall to Tier 2 instead of crashing on `node:` protocol imports.
- **Removed unnecessary timeout from statusline**: Claude Code cancels in-flight statusline scripts on new updates per [official docs](https://code.claude.com/docs/en/statusline), so `timeout` guard is unnecessary (kept on hooks where it's still needed).

---

## [9.7.3] - 2026-03-19

### Fixed

- **`local` outside function** — `octopus-statusline.sh` used `local wt_suffix` at script scope, which aborts under `set -e`. Broke the entire bash statusline fallback when worktrees were active. Same bug in `scheduler-security-gate.sh` silently bypassed file path restrictions.
- **Atomic credential writes** — `writeBackCredentials` now uses temp file + `renameSync` with `mode: 0o600`. Prevents concurrent sessions from clobbering `~/.claude/.credentials.json`.
- **Atomic cache writes** — `writeUsageCache` uses temp + `renameSync` to prevent torn JSON from concurrent sessions.
- **Python injection in context-awareness** — Bridge file path was interpolated into `python3 -c` string literal. Now passed via `os.environ['BRIDGE_PATH']`.
- **Unsafe `/tmp` glob removed** — `context-awareness.sh` no longer falls back to `ls -t /tmp/octopus-ctx-*.json`. Exits cleanly when `CLAUDE_SESSION_ID` is unset.
- **5 additional timeout guards** — `plan-mode-interceptor.sh`, `scheduler-security-gate.sh`, `sysadmin-safety-gate.sh`, `telemetry-webhook.sh`, `agent-teams-phase-gate.sh` now have the `command -v timeout` fallback pattern. Total: 10 hooks hardened.
- **HUD stdin timeout** — `readStdin()` now uses `Promise.race` with a 5s guard to prevent indefinite hang on unclosed pipes.
- **`contextBar` clamp** — `Math.min(10, Math.max(0, ...))` prevents `RangeError` if pct > 100 reaches the function.
- **Bridge file permissions** — Written with `umask 0177` (owner-only) instead of default umask.

---

## [9.7.2] - 2026-03-19

### Added

- **Smart HUD columns**: `smartColumns()` auto-detects context and adjusts visible columns — hides Cost for OAuth subscription users, shows Cache/Session/Changes/Tokens only when data is meaningful. Column factory pattern ensures config-ordered rendering. `"smart": true` is the default; set `"smart": false` in `.hud-config.jsonc` for manual control.
- **Octo brand column**: New `Octo:` column (always first) displays octopus icon, plugin version, and effort level dot. Model column moved to second position, Context column anchors the end.
- **Context bridge session_id fix**: Both statusline hooks now extract `session_id` from stdin JSON instead of relying on `CLAUDE_SESSION_ID` env var (which isn't set for statusLine commands). Context-awareness hook falls back to finding the most recent bridge file when env var is missing.
- `test-hud-smart-mode.sh` — 31 tests across 5 groups covering timeout fallback, smart mode, Octo column, context bridge, and functional HUD output.

### Fixed

- **Timeout fallback for macOS**: All 6 hook files now check `command -v timeout` before using GNU `timeout`. Falls back to plain `cat` when `timeout` (GNU coreutils) isn't installed — fixes silent stdin read failures on stock macOS that caused model showing "unknown" and 0% context in the statusline.

---

## [9.6.1] - 2026-03-19

### Added

- **Enhanced HUD rewrite**: Full async rewrite of `octopus-hud.mjs` (295 → 880 lines). Concurrent API/transcript/version fetching via `Promise.all`. First call ~300-500ms, subsequent calls <10ms (all cache hits).
- **Rate limit tracking**: 5h/7d usage from Anthropic OAuth API with color-coded percentages and reset countdown timers. Credential reading from `.credentials.json` with macOS Keychain fallback. Token refresh on expiry. 60s/15s cache TTLs.
- **Transcript-based agent tracking**: Parses JSONL transcripts for running/completed agents (Task/proxy_Task tool_use blocks). Background agent tracking, stale agent detection (30 min timeout), max 100 agents in memory. Agent detail tree with `├─`/`└─` prefixes showing type, model, elapsed time, description.
- **Cache hit rate**: Computes cache read vs total tokens from `current_usage` fields. Displayed as percentage with color coding.
- **Version check**: Fetches latest Claude Code version from npm registry with 1h cache. Shows update indicator dot when current differs from latest.
- **Configurable column system**: `~/.claude-octopus/.hud-config.jsonc` with JSONC parsing (supports `//` comments). 14 columns available, 5 default ON. Vertical (2-row labels+values) and horizontal (single-row compact) layouts.
- **Tailwind color palette**: Replaced basic ANSI (31-37) with 24-bit Tailwind colors — Emerald-600 for good, Amber-600 for warning, Red-600 for critical, Slate-600/700/800 for data/labels/separators.
- Updated `test-enhanced-hud.sh` — 30 tests across 6 groups covering rate limit functions, display, enhanced features, Octopus preserved functions, config system, and layout support.

---

## [9.6.0] - 2026-03-18

### Added

- **Enhanced statusline**: Gradient context bar (`▰▱`), auto-compact warning indicators (`⚠` at 80%, `💀` at 90%), active agent name display, project state from `.octo/STATE.md` when idle. Performance-cached with 2s TTL.
- **Workflow-aware context warnings**: `context-awareness.sh` now reads session.json and gives phase-specific advice (probe→"use /octo:quick", tangle→"split into smaller /octo:develop", ink→"focus on verification"). New 80% AUTO_COMPACT severity level.
- **Session handoff file**: `.octo-continue.md` auto-written on PreCompact and SessionEnd. Contains workflow state, pending work, key decisions, blockers, and resume instructions. Read by `/octo:resume`.
- **Enhanced intent detection**: `user-prompt-submit.sh` now has HIGH/LOW confidence levels (2+ keyword hits = HIGH). HIGH confidence injects persona context (security auditor, code reviewer, debugger, TDD orchestrator hints). Provider pre-warming writes `primed_providers` to session.json.
- **New script**: `scripts/write-handoff.sh` — standalone handoff file generator.
- 4 new test suites: enhanced-hud (18), context-awareness-v2 (14), handoff (12), prompt-submit-v2 (12) — 56 new assertions.

---

## [9.5.0] - 2026-03-18

### Added

- **Stdin timeout guards**: All 6 hook files now use `timeout 3 cat` instead of bare `cat` reads, preventing hook hangs on stdin stalls.
- **50KB output guard**: `guard_output()` in `lib/utils.sh` redirects oversized output to temp files with `@file:` pointers. Wired into `aggregate_results()` and `synthesize_probe_results()`.
- **Agent permission audit**: Removed `Agent` tool from 7 read-only agents (backend-architect, code-reviewer, security-auditor, performance-engineer, docs-architect, cloud-architect, database-architect). Added `readonly: true` to 6 agents. Removed `Bash` from security-auditor.
- **Context bridge**: Both statusline hooks (bash + Node.js HUD) now write `/tmp/octopus-ctx-$SESSION.json` with context usage data for cross-hook awareness.
- **Context awareness hook**: New `hooks/context-awareness.sh` (PostToolUse, blanket) warns at 65% (WARNING) and 75% (CRITICAL) context usage. Debounced every 5 tool calls with severity escalation bypass.
- **Structured return contracts**: All 10 agent files now have `## Output Contract` with COMPLETE/BLOCKED/PARTIAL status markers and per-agent customized sections.
- **Contract compliance scoring**: `score_result_file()` Factor 5 adds up to 20 pts for structured status markers in agent output.
- **Compound init command**: `init-workflow)` dispatch case returns full environment bundle (providers, models, capabilities, files, paths) as JSON in a single call.
- **Smart router renamed**: `/octo:octo` → `/octo:auto`. The old `/octo:octo` command remains as a legacy redirect. 40 commands total.
- 6 new test suites: stdin-timeout-guards (12), output-guard (6), agent-permissions-audit (12), context-bridge (12), agent-return-contracts (32), compound-init (17) — 91 new assertions.

---

## [9.4.3] - 2026-03-17

### Fixed

- Legacy `claude-octopus` install detection in doctor and preflight — users who installed before the v9.0 rename to `octo` now see a clear diagnostic with the uninstall/reinstall command. (#196)

---

## [9.4.2] - 2026-03-17

### Changed

- **Round 2 speed optimization**: 26 echo|grep → bash builtins, 22 $(cat) → $(<), $(date +%s) caching in 5 hot functions, 124 separator literals → variables. ~100 additional forks eliminated per workflow.
- **Combined with Round 1 (v9.4.1)**: orchestrate.sh goes from ~900 subshell forks per workflow to ~70 — a 92% reduction in subprocess overhead.

### Removed

- `archive_usage_session()` dead function and `cost-archive` command (deprecated with message).

### Fixed

- Missing file guard on `generate_factory_scenarios()` — `$(<)` without `[[ -f ]]` check could abort under `set -e`.
- Newline regression in `match_routing_rule` keyword matching — `grep -qw` treated newlines as word boundaries, space-padding didn't.
- Redundant dual `nocasematch` blocks in `parse_factory_spec` merged into single block + `case` statement.
- `_classify_smoke_error` nocasematch wrapped in subshell to prevent leak on future early returns.
- Timing skew: `start_time_ms` in `spawn_agent` and `probe_single_agent` restored to fresh `$(date +%s)` (metrics accuracy over micro-optimization).

---

## [9.4.1] - 2026-03-17

### Changed

- Flag pruning, speed optimization (~750 fewer subshell forks), pre-existing test fixes

---

# Changelog

## [9.4.0] - 2026-03-17

### Added

- **Four-way AI debates**: Sonnet now participates as a permanent 4th debater alongside Codex, Gemini, and Claude/Opus. Dispatched via `Agent(model: "sonnet", run_in_background: true)` — runs in parallel, no added latency, no extra cost. Skill version v4.7 → v4.8.
- **Auto code review + E2E verification**: After any `/octo:develop`, `/octo:embrace`, or `/octo:deliver` workflow completes, two Sonnet agents automatically launch in parallel — one code reviewer, one E2E tester. Findings presented before the "what next?" prompt. No manual request needed.
- **Monolith guard test**: `tests/smoke/test-monolith-guard.sh` (15 tests) enforces orchestrate.sh line count threshold, lib file existence, no function duplication, and source guards.
- **Test infrastructure helper**: `tests/helpers/grep-octopus.sh` searches across `orchestrate.sh` + `lib/*.sh` so tests survive function extraction.

### Changed

- **Wave 1 decomposition**: Extracted 3 new lib modules from orchestrate.sh (22,668 → 22,377 lines):
  - `lib/utils.sh` (183 lines): json_extract, json_escape, sanitize_external_content, validate_agent_command, validate_output_file, sanitize_review_id, secure_tempfile
  - `lib/similarity.sh` (103 lines): jaccard_similarity, extract_headings, check_convergence, generate_bigrams, bigram_similarity
  - `lib/models.sh` (129 lines): get_model_catalog, is_known_model, get_model_capability, list_models

### Fixed

- **`list_models --tier` parsing bug**: `shift` inside a `for` loop produced wrong results. Replaced with proper `while [[ $# -gt 0 ]]` pattern.
- **`log()` forward-reference in utils.sh**: Extracted functions called `log()` before it was defined. Added `_utils_log()` fallback that uses stderr when `log()` isn't available.
- **`validate_output_file` silent failure**: When `RESULTS_DIR` was unset, validation silently rejected all files with a misleading error. Now explicitly checks and reports the missing variable.
- **9 review pipeline bugs** silently dropping all findings (#182-#190) — see v9.3.1 below for individual fixes.

---

## [9.3.1] - 2026-03-16

### Fixed

- **awk filter drops codex exec clean stdout**: The output filter expected a `--------` header separator that `codex exec` doesn't emit on stdout. Now detects clean stdout and passes through directly. (#182)
- **claude-sonnet agent `-m` flag rejected**: Claude CLI v2.1.76 requires `--model` (long form). Updated `claude-sonnet`, `claude-opus`, and `claude-opus-fast` agent commands. (#183)
- **log() INFO/WARN pollutes captured output**: `log()` INFO and WARN levels wrote to stdout, corrupting function return values captured via `$()`. Now all log levels write to stderr. (#183)
- **check_provider_health uses removed `codex auth status`**: Codex CLI v0.114 removed `auth status`. Now checks `~/.codex/auth.json` directly. (#184)
- **Claude CLI not found in non-interactive shells**: When `~/.local/bin` isn't on PATH, the script now probes common install locations before falling back. (#185)
- **Round 1 findings parser feeds full markdown to jq**: The parser now extracts the `## Output` section from result files before JSON parsing, instead of feeding the entire markdown document to jq. (#186)
- **Gemini provider status never written**: Round 1 findings collection now writes provider status events for all agent types, not just codex. (#187)
- **LLM JSON wrapped in markdown fences breaks jq**: Added fence stripping after `run_agent_sync` in Rounds 2, 3 (debate), and 3 (synthesis). (#188)
- **PURPLE unbound variable crashes setup_wizard**: Added `PURPLE` color variable as alias for `MAGENTA`. (#189)
- **Round 1 `wait` returns immediately**: Replaced bare `wait` (which only catches direct children) with polling for `## Status:` markers in result files, with 5-minute timeout. (#190)

---

## [9.3.0] - 2026-03-16

### Added

- **Search spiral guard**: Research agents get a prompt-level instruction preventing search loops without synthesis. Unconditional in `probe_single_agent()`, role-gated (`researcher`) in `spawn_agent()`.
- **Per-role token budget proportions**: `get_role_budget_proportion()` scales `enforce_context_budget()` by role — implementers/researchers get 60%, planners/reviewers 40%, verifiers/synthesizers 25%. Prevents one chatty agent from starving others.
- **Heuristic learning**: `record_run_pattern()` records file co-occurrence from successful agent runs to `~/.claude-octopus/.octo/patterns.jsonl` (capped 200 entries). `build_heuristic_context()` injects "when modifying X, successful runs usually first read Y" hints (≤500 chars) into future prompts. Kill switch: `OCTOPUS_HEURISTIC_LEARNING=off`.

### Changed

- `enforce_context_budget()` now accepts an optional second parameter (`role`) for budget scaling.

---

## [9.2.2] - 2026-03-16

### Fixed

- **Codex subagent dispatch intercepted by Codex superpowers skill system**: When Codex CLI has "superpowers" skills installed, its skill system intercepts octo's dispatched prompts and forces its own brainstorming workflow instead of responding directly. Fixed by prepending a user-level override preamble to all Codex dispatches that tells the model to skip skills. (#176)

---

## [9.2.1] - 2026-03-16

### Fixed

- **jq parse error in `code-review`**: Bash `${1:-{}}` parameter expansion appended an extra `}` to the JSON profile string, causing jq parse errors. Fixed by quoting the default value. (#172)
- **"Argument list too long" with large diffs**: The review pipeline passed prompts (including embedded diffs) as CLI arguments, exceeding `ARG_MAX` for PRs with >2000 lines. All agent types now use stdin-based prompt delivery. (#173)

---

## [9.2.0] - 2026-03-15

### Changed

- smart dispatch, blind spot library, skill name fix

---

## [9.1.0] - 2026-03-14

### Changed

- brainstorm Team mode multi-LLM, COMMAND-REFERENCE.md update

---

## [9.0.1] - 2026-03-14

### Fixed

- **Plugin install/uninstall mismatch**: Aligned `marketplace.json` plugin name from `"claude-octopus"` to `"octo"` to match `plugin.json`. Install command is now `octo@nyldn-plugins`. Fixes `/plugin uninstall` and `/plugin update` failures.

---

## [9.0.0] - 2026-03-14

### Added

- **6 new `SUPPORTS_*` detection flags** (100 total, 31 `version_compare` blocks) from CC v2.1.76.
- **v2.1.76**: `SUPPORTS_MCP_ELICITATION` (MCP servers can request structured user input mid-task), `SUPPORTS_ELICITATION_HOOKS` (Elicitation and ElicitationResult hook events), `SUPPORTS_WORKTREE_SPARSE_PATHS` (`worktree.sparsePaths` setting for sparse checkout), `SUPPORTS_POST_COMPACT_HOOK` (PostCompact hook event fires after compaction), `SUPPORTS_EFFORT_COMMAND` (`/effort` slash command for mid-session effort adjustment), `SUPPORTS_BG_PARTIAL_RESULTS` (killing background agent preserves partial results).
- `test-cc-v2176-sync.sh` — tests covering declarations, detection block, logging, wiring, doctor checks, and version comments.
- `test-command-meta-prompt.sh` — 8 tests: file integrity, frontmatter, skill reference, core techniques, registration.
- `test-command-prd-score.sh` — 11 tests: file integrity, frontmatter with arguments, scoring categories A-D, 100-point framework, grade scale, registration.
- `test-command-staged-review.sh` — 9 tests: file integrity, frontmatter, no broken references, compliance block, skill reference, cross-reference validation, registration.

### Wired

- `spawn_agent()`: Debug log when `SUPPORTS_BG_PARTIAL_RESULTS` confirms background agent partial result preservation (CC v2.1.76+).
- `/octo:doctor`: Surfaces `/effort` command availability for mid-session effort adjustment (CC v2.1.76+).
- `/octo:doctor`: Checks `worktree.sparsePaths` setting in `~/.claude/settings.json` for large monorepo optimization (CC v2.1.76+).
- `/octo:doctor`: Surfaces MCP elicitation capability (CC v2.1.76+).
- `/octo:doctor`: Warns about `--plugin-dir` behavioral change — one path per flag in v2.1.76+ (use repeated flags for multiple dirs).
- `/octo:doctor`: Detects **claude-mem** companion plugin (version, "pass" status) — surfaces MCP tool availability for cross-session memory.
- `scripts/claude-mem-bridge.sh`: Integration bridge for claude-mem HTTP API — `available`, `search`, `observe`, `context` commands. All operations non-blocking and fault-tolerant.
- `save_session_checkpoint()`: Writes phase completion observations to claude-mem when available (non-blocking background POST).
- `session-start-memory.sh`: Queries claude-mem for recent project context at session start and surfaces it.
- 6 skill/command files with claude-mem MCP tool hints: `flow-discover.md`, `flow-define.md`, `flow-develop.md`, `flow-deliver.md`, `skill-debate.md`, `skill-deep-research.md`.
- `/octo:octo` smart router: Added claude-mem search hint for routing correction learning.

### Changed

- `/octo:review` default focus: `["correctness"]` → `["correctness","security","architecture","tdd"]` — all areas reviewed by default.
- `/octo:review` auto-skips interactive prompts when `OCTOPUS_WORKFLOW_PHASE` is set (pipeline context from `/octo:develop`, `/octo:embrace`, etc.).
- `/octo:review`: Added "All areas (Recommended)" focus option — users no longer need to select 4 options individually.
- `/octo:brainstorm`: Added Solo/Team mode selection — Team mode dispatches parallel brainstorm queries to available providers for diverse AI perspectives.
- `/octo:prd`: Phase 1 research now dispatches parallel queries to available providers (Codex for technical patterns, Gemini for market landscape) when multi-provider is available.
- `/octo:prd-score`: Added optional "Rigorous" multi-AI scoring mode — 2-3 providers score independently, then consensus synthesis reduces single-model bias.
- `/octo:staged-review`: Rewritten with mandatory compliance block, AskUserQuestion for scope selection, interactive next steps, and correct related command references.
- `/octo:model-config`: Updated stale `GPT-5.3-Codex-Spark` references to `GPT-5.4` to match current orchestrate.sh model mappings.

### Fixed

- `/octo:staged-review`: Removed broken references to non-existent `/octo:verify` and `/octo:ship` commands — replaced with `/octo:deliver` and `/octo:review`.
- `/octo:review`: Codex auth preflight via `check_codex_auth_freshness()` — warns user before silent fallback to claude-sonnet.
- `/octo:review`: Visible `⚠` warnings when Codex falls back to claude-sonnet in Round 2 (verification) and Round 3 (debate gate). Users now see why Codex API usage doesn't change.

---

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
