# Claude Octopus - System Instructions

> **Note:** This file provides context when working directly in the claude-octopus repository.
> For deployed plugins, visual indicator instructions are embedded in each skill file
> (flow-discover.md, flow-define.md, flow-develop.md, flow-deliver.md, skill-debate.md).

## Visual Indicators (MANDATORY)

When executing Claude Octopus workflows, you MUST display visual indicators so users know which AI providers are active and what costs they're incurring.

### Indicator Reference

| Indicator | Meaning | Cost Source |
|-----------|---------|-------------|
| 🐙 | Claude Octopus multi-AI mode active | Multiple APIs |
| 🔴 | Codex CLI executing | User's OPENAI_API_KEY |
| 🧭 | Antigravity CLI executing | User's Antigravity access/subscription |
| 🟣 | Perplexity Sonar web search | User's PERPLEXITY_API_KEY |
| 🔵 | Claude subagent processing | Included with Claude Code |

### When to Display Indicators

Display indicators when:
- Invoking any `/octo:` command
- Running `orchestrate.sh` with any workflow (probe, grasp, tangle, ink, embrace, etc.)
- User triggers workflow with "octo" prefix ("octo research X", "octo build Y")
- Executing multi-provider operations

Provider emoji are required in status banners, provider rows, compact banners,
and result attribution labels. Narrative prose may use provider names without
emoji.

### Required Output Format

**Before starting a workflow**, output this banner:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - [Workflow Type]
[Phase Emoji] [Phase Name]: [Brief description of what's happening]

Providers:
🔴 Codex CLI - [Provider's role in this workflow]
🧭 Antigravity CLI - [Provider's role in this workflow]
🔵 Claude - [Your role in this workflow]
```

**Phase emojis by workflow**:
- 🔍 Discover/Probe - Research and exploration
- 🎯 Define/Grasp - Requirements and scope
- 🛠️ Develop/Tangle - Implementation
- ✅ Deliver/Ink - Validation and review
- 🐙 Debate - Multi-AI deliberation
- 🐙 Embrace - Full 4-phase workflow

### Compact Mode

When `OCTOPUS_COMPACT_BANNERS=true` is set, use a condensed single-line banner instead:
```
🐙 Discover — Multi-provider research | 🔴🧭🔵
```

This is preferred for repeat users who don't need the full provider block every time.

### Examples (Standard Mode)

**Research workflow:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching OAuth authentication patterns

Providers:
🔴 Codex CLI - Technical implementation analysis
🧭 Antigravity CLI - Ecosystem and community research
🔵 Claude - Strategic synthesis
```

**Build workflow:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
🛠️ Develop Phase: Building user authentication system

Providers:
🔴 Codex CLI - Code generation and patterns
🧭 Antigravity CLI - Alternative approaches
🔵 Claude - Integration and quality gates
```

**Review workflow:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation mode
✅ Deliver Phase: Reviewing authentication implementation

Providers:
🔴 Codex CLI - Code quality analysis
🧭 Antigravity CLI - Security and edge cases
🔵 Claude - Synthesis and recommendations
```

**Debate:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - AI Debate Hub
🐙 Debate: Redis vs Memcached for session storage

Participants:
🔴 Codex CLI - Technical perspective
🧭 Antigravity CLI - Ecosystem perspective
🔵 Claude - Moderator and synthesis
```

### During Execution

When showing results from each provider, prefix with their indicator:

```
🔴 **Codex Analysis:**
[Codex findings...]

🧭 **Antigravity Analysis:**
[Antigravity findings...]

🔵 **Claude Synthesis:**
[Your synthesis...]
```

### Why This Matters

Users need to understand:
1. **What's running** - Which AI providers are being invoked
2. **Cost implications** - External CLIs (🔴 🧭) may use provider access or incur cost
3. **Progress tracking** - Which phase of the workflow is active

Without indicators, users have no visibility into what's happening or what they're paying for.

---

## Provider Readiness Contract

Provider Registry 2.0 is the authority for provider identity, capabilities,
authentication mode, detection, and health routing. Use
`scripts/helpers/check-providers.sh` for the documented machine-readable
admission protocol or `scripts/helpers/preflight.sh --json` for structured
readiness objects.

Static checks are local-only. Live checks run only after an explicit `--live`
request and must remain bounded. Doctor, setup, preflight, and provider
detection render the shared result objects; they must not independently probe
binaries, credentials, models, quota, or provider services. Diagnostics belong
on stderr, and readiness output must never contain credential values.

---

## File Creation Policy (CRITICAL)

**NEVER create temporary, progress, or working files in the plugin directory.**

### Prohibited File Patterns

The following file types MUST NEVER be created in the plugin directory:
- `PHASE*_PROGRESS.md` - Phase progress tracking
- `PHASE*_COMPLETE.md` - Phase completion markers
- `*_PROGRESS.md` - Any progress tracking files
- `*_TODO.md` - Working todo lists
- `*_NOTES.md` - Development notes
- `scratch_*.md` - Scratch files
- `temp_*.md` - Temporary files
- `WIP_*.md` - Work-in-progress markers

### Where to Create Working Files

**Use the scratchpad directory for ALL temporary/working files:**

```bash
# Scratchpad directory (auto-managed by Claude Code)
~/.claude/scratchpad/[session-id]/

# Example paths
~/.claude/scratchpad/abc123/phase1-progress.md
~/.claude/scratchpad/abc123/implementation-notes.md
~/.claude/scratchpad/abc123/todo-list.md
```

### Plugin Directory: Permanent Files Only

Only create files in the plugin directory that are:
- Part of the permanent codebase (commands, skills, agents, hooks)
- User-facing documentation (README.md, CHANGELOG.md, docs/)
- Build/config files (package.json, tsconfig.json, .gitignore)
- Test files in `tests/` directory

### Enforcement

If you need to track progress or create working files:
1. **Always use the scratchpad directory**
2. **Never commit working files to git**
3. **Reference scratchpad files by full path when discussing them**

**Example - WRONG:**
```bash
# ❌ Never do this
echo "Progress: 50%" > PHASE1_PROGRESS.md
```

**Example - CORRECT:**
```bash
# ✅ Always do this
echo "Progress: 50%" > ~/.claude/scratchpad/$(cat ~/.claude/session-id)/phase1-progress.md
```

---

## Workflow Quick Reference

| Command/Trigger | Workflow | Indicators |
|-----------------|----------|------------|
| `octo research X` | Discover | 🐙 🔍 🔴 🟡 🔵 |
| `octo define X` | Define | 🐙 🎯 🔴 🟡 🔵 |
| `octo build X` | Develop | 🐙 🛠️ 🔴 🟡 🔵 |
| `octo review X` | Deliver | 🐙 ✅ 🔴 🟡 🔵 |
| `octo debate X` | Debate | 🐙 🔴 🟡 🔵 |
| `/octo:embrace X` | All 4 phases | 🐙 (all phase emojis) |

---

## Provider Detection

Before running workflows, check provider availability with
`scripts/helpers/check-providers.sh`, which is the single source of truth for
how each provider is detected (binary presence, API key, and auth state).

If a provider is unavailable, note it in the banner:
```
Providers:
🔴 Codex CLI - [role] (unavailable - skipping)
🧭 Antigravity CLI - [role]
🔵 Claude - [role]
```

---

## Cost Awareness

Always be mindful that external CLIs cost money:
- 🔴 Codex: ~$0.01-0.30 per query depending on model (GPT-5.6 Sol $4/$20 MTok — frontier default, Terra $2/$12, Luna $0.20/$1.20). Explicit-only GPT-6 Astra costs $10/$50; above 272K input tokens its full request uses 2x input and 1.5x output pricing.
- 🧭 Antigravity CLI (`agy`): Included with the user's Antigravity access/subscription; backend cost depends on selected `OCTOPUS_AGY_MODEL`. Because Antigravity's model list is service-owned, explicit pins should use labels returned by `agy models` (for example `Gemini 3.5 Flash (Low)`) or `default`/`agy/default` to use the CLI default.
- 🟣 Perplexity: ~$0.01-0.05 per query (Sonar Pro $3/$15 MTok, Sonar $1/$1 MTok)
- 🔵 Claude (Sonnet 5): Standard Claude seat, $2/$10 per MTok; included where the user's Claude Code subscription covers it
- 🔵 Claude (Fable 5.1, Mythos-class, opt-in via `OCTOPUS_OPUS_MODEL=claude-fable-5-1`): **$10/$50 per MTok** — 2x Opus 5 cost. 1M context, 128K output. Never auto-selected. The preserved `claude-fable-5` ID remains supported. Note: Anthropic retains prompts/outputs up to 30 days for safety classifiers. When pinned, apply the dispatch profile in `skills/blocks/fable5-prompting.md` (prompt anti-patterns, effort discipline, refusal fallback, judgment routing).
- 🔵 Claude (Opus 5, default when `SUPPORTS_OPUS_5=true`): $5/$25 per MTok input/output. 1M context, 128K output. Use `high` effort by default; raise it only for a bounded capability-sensitive step.
- 🔵 Claude (Opus 5 Fast): $10/$50 per MTok — 2x standard cost. Use only when latency matters.
- 🔵 Claude (Opus 4.7, legacy/current-minus-one): $5/$25 per MTok input/output. Used automatically on Claude Code versions before 2.1.154 when supported.
- 🔵 Claude (Opus 4.6, legacy): $5/$25 per MTok — still selectable via `OCTOPUS_OPUS_MODEL=claude-opus-4.6` or `claude-opus-legacy` agent type
- 🔵 Claude (Opus 4.6 Fast, legacy): **$30/$150 per MTok** (6x standard) — lower latency, extra-usage billing for pinned 4.6 sessions.
- 🟤 OpenCode: Variable cost — free for native models, uses backend provider pricing when routing to OpenAI/Google

Note: API availability and subscription/OAuth availability differ by model and account. GPT-5.6 routing requires Codex CLI v0.144.0+; Astra requires v0.153.1+ and fails closed when the installed version cannot be identified.

Host-seat Fable 5.1 pins require Claude Code v2.1.255 or newer so the client recognizes the model and its 1M context window. The independent `claude-agent` SDK path instead requires `CLAUDE_SDK_API_KEY` and the `claude-agent` executable, with no Claude Code version floor. Its headless `claude` CLI fallback must be v2.1.255 or newer.

For simple tasks that don't need multi-AI perspectives, suggest using Claude directly without orchestration.

### Opus 5 Effort Levels (Claude Code v2.1.219+)

Opus 5 defaults to `high` effort. The plugin keeps automatic phase routing at `high`; use `OCTOPUS_EFFORT_OVERRIDE` for a bounded step, or `OCTOPUS_OPUS5_AUTO_XHIGH=1` to restore the legacy automatic xhigh behavior:

- **probe / discover** — `high`
- **grasp / define** — `high`
- **tangle / develop** — `high`
- **ink / deliver** — `high`

`xhigh` falls back to `high` on older models where Claude Code does not expose it. Override per-session with `OCTOPUS_EFFORT_OVERRIDE=low|medium|high|xhigh|max`.

### Fable 5.1 Effort and Refusal Handling (opt-in pin only)

The phase table above is Opus 5 guidance and does not carry over to a `claude-fable-5-1` or preserved `claude-fable-5` pin. On Fable, run `high` everywhere: effort applies per tool call, so `xhigh` does not extend runs — it makes each step overthink and widen scope, at 2x the cost. Raise effort only for a single capability-sensitive step.

When a Fable pin is detected through `OCTOPUS_OPUS_MODEL`, `OCTOPUS_CLAUDE_SDK_MODEL`, `OCTOPUS_CLAUDE_MODEL`, or `CLAUDE_MODEL`, orchestrate.sh auto-enables three guards via `scripts/lib/fable5.sh` and prints a one-line banner (`OCTOPUS_FABLE5_MODE=off` disables ordinary-pin guards; `=on` forces them):

- **Security reroute** — by default, security-audit dispatches (security-auditor role, squeeze workflow) do not run on Fable; the model resolver and dispatch swap in `claude-opus-5`. `OCTOPUS_FABLE5_MODE=off` is an explicit exception for ordinary pins, while exact model-qualified Fable security seats still fail closed.
- **Effort clamp** — `xhigh`/`max` clamp to `high` for opus-seat Fable dispatches, including explicit `OCTOPUS_EFFORT_OVERRIDE` values.
- **Refusal retry** — the claude-sdk shim retries a refused/empty Fable 5 dispatch once on `claude-opus-5` (`OCTOPUS_FABLE5_NO_RETRY=1` to opt out, `OCTOPUS_FABLE5_FALLBACK_MODEL` to pin another fallback) instead of rewording the prompt toward the classifier.

**Prompt hygiene (not machine-enforced):** never ask Fable 5 to reveal or transcribe its reasoning (triggers the `reasoning_extraction` refusal), avoid token countdowns, and drop "CRITICAL"/"MUST" emphasis unless strict compliance is required. Full profile: `skills/blocks/fable5-prompting.md`.

### Legacy Fast Opus preference

Claude's spawned `--print` CLI does not expose a supported `--fast` flag.
`OCTOPUS_OPUS_MODE=fast` remains recognized as a legacy preference, but it logs
a compatibility warning and uses standard subprocess dispatch. It does not
select a faster or higher-priced subprocess tier. `OCTOPUS_OPUS_MODE=standard`
also uses the standard command contract. Use `OCTOPUS_OPUS_MODEL` to pin a
specific supported model.

### Dynamic Workflows (Claude Code v2.1.154+)

Claude Code dynamic workflows are the right native path for huge single-Claude codebase migrations. Use Octopus when the job needs multi-provider disagreement, council deliberation, adversarial review, external model validation, or provider-specific blind-spot checks. Do not wrap a native dynamic workflow inside Octopus unless the handoff boundary is explicit.

---

## Auto Memory & Persistent Memory Integration (Claude Code v2.1.32+, enhanced in v2.1.33+)

Claude Code's auto memory (`~/.claude/projects/.../memory/MEMORY.md`) persists across conversations. When `SUPPORTS_PERSISTENT_MEMORY` is detected (v2.1.33+), memory persistence is guaranteed across sessions. Record the following in auto memory:

- **User's preferred autonomy mode** (interactive vs autonomous workflow execution)
- **Provider availability** (which CLIs are installed, auth methods configured)
- **Frequently used commands** (e.g., user prefers `/octo:quick` over full embrace)
- **Past project contexts** (tech stack, coding conventions, deployment targets)
- **Model preferences** (whether user prefers Opus 4.6 for premium tasks)

This enables faster workflow startup by skipping provider detection and preference questions in subsequent sessions.

---

## Enforcement Best Practices

Skills use the **Validation Gate Pattern** to ensure multi-LLM dispatch actually executes:

1. **Pre-check**: Run `check-providers.sh` to detect available providers before dispatch
2. **Dispatch**: Call `orchestrate.sh probe-single` per provider via background Agent subagents
3. **Validate**: After dispatch, verify synthesis files exist (`find ~/.claude-octopus/results/ -name "probe-synthesis-*" -mmin -10`)
4. **Fail loud**: If no synthesis files found, report "VALIDATION FAILED — multi-LLM dispatch did not execute" instead of silently falling back to Claude-only

> Developer reference (modular config, E2E testing, enforcement patterns): see `docs/DEVELOPER.md`

---

## Repo Orientation for Agents (read before editing)

The rules below encode failures that have already cost real CI rounds. Every one is enforced by a CI check; none of them is guesswork.

### Derived artifacts (never hand-edit)

| Generated file | Regenerate with | CI check that fails if stale |
|----------------|-----------------|------------------------------|
| `.claude-plugin/marketplace.json` (octo description + counts) | `./scripts/sync-marketplace.sh` | Smoke job "Verify marketplace.json is up to date" |
| `README.md`, `.claude-plugin/README.md`, and `PRODUCT.md` current facts | `./scripts/sync-readme.py` (included in `make sync`) | `tests/unit/test-readme-release-sync.sh` |

After changing commands, skills, agents, plugin metadata, release notes, models,
providers, or public facts: run `make sync`. During development, run focused
suites. Before an ordinary branch push, run `make ci-changed`; its checked-in
manifest always runs sync, smoke, packaging, and reachability checks and fails
closed to the full matrix for shared or unmapped changes. Before merge and
release, run `make ci-local` for sync-check plus the local smoke, unit, and
integration suites. Run the separate portability and symlink jobs in hosted CI.

### Hard rules (each one has broken a real PR)

- Never hand-write component counts into `plugin.json`'s description; the marketplace generator appends its own counts and `--check` fails on the collision. The generator derives the marketplace blurb from `plugin.json`'s description — to change it, edit `plugin.json` and run `make sync`, never `marketplace.json` itself.
- Shell scripts and Python helpers stay `100755`. Verify before push: `git diff origin/main...HEAD --summary | grep "mode change"` must be empty. CI enforces this (Portability Lint job; `allow-mode-change` PR label bypasses when intentional). Local test runs (`make ci-local`, some unit suites) chmod test fixtures as a side effect — recheck modes after every local test run, not just after editing.
- Provider case globs are order-sensitive: `claude-sdk*` must appear before `claude*`. A shadowed arm fails silently.
- Provider identity and capabilities belong in both registry tables. Keep the
  rows in parity and let `octo_provider_validate_contracts` reject incomplete
  registrations.
- In shell, quote env assignments as whole arguments: `"SOME_API_KEY=${VAR}"`, not `SOME_API_KEY="${VAR}"`. The expert-review secret scanner false-positives on the latter.
- Never put generated text or Markdown directly in shell GitHub-body arguments such as `--body` or `-f body=`. Stream it to `./scripts/safe-gh-comment.sh --repo OWNER/REPO ... -` on stdin (or pass a private file); the helper snapshots and validates outbound text before a silent write.
- CI waiters must assert the named required checks (Smoke Tests, Unit Tests, Integration Tests) are PRESENT and terminal. `all(.bucket != "pending")` over an empty list is vacuously true and fires instantly.
- Timeout-test fixtures must run LONGER than the pass bound, or a broken timeout false-passes. A test must be able to fail; prove it can.
- Tag releases on the squash-merge commit on `main`, never on the branch head. Full release procedure: `RELEASING.md`.
- Fork PRs stall at `action_required` after every push; approve with `gh api -X POST repos/nyldn/claude-octopus/actions/runs/<id>/approve`.
- Provider wiring is a 7-point checklist across 5 files: `docs/PROVIDERS.md`. Do not wing it from one example.
- MCP provider environment names come from
  `config/provider-env-allowlist.json`; keep its adapter tests green when it
  changes.

### Memory ruling (single source of truth)

beads (`bd`) is the system of record. The Session Completion push mandate in this file is the "explicit authority" that bd's conservative-profile guidance asks for; the two do not conflict in this repo. Known failure mode: pending Dolt schema migrations block ALL bd writes with "refusing to auto-apply ... migrations". Do NOT run the migration (single-designated-migrator rule); instead record the work in your session handoff, note the blockage explicitly, and flag it to the maintainer. Do not silently drop tracking.

## Cross-Harness Continuity

`bd` is the task system of record. `AI_AGENT_HANDOFF.md` is the committed,
harness-neutral context packet for Claude Code, Codex, Copilot, OpenCode, and
other coding agents. It records the active branch, current decisions, evidence,
known blockers, and exact next action; it does not replace issue tracking.

At session start, read `RTK.md`, this file, `AI_AGENT_HANDOFF.md`, `git status`,
and the relevant `bd` issue before editing. For model-routing work, also read
`docs/MODEL-ROUTING-STRATEGY.md`. At session end, update the handoff with
verified test results, commit/push state, and remaining work.

Harness-local files such as `.octo-continue.md` may be generated or stale. Do
not treat them as the repository source of truth and do not overwrite an
untracked copy you did not create.

---

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
