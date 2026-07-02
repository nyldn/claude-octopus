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
| 🟡 | Gemini CLI executing | User's GEMINI_API_KEY |
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
🟡 Gemini CLI - [Provider's role in this workflow]
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
🐙 Discover — Multi-provider research | 🔴🟡🔵
```

This is preferred for repeat users who don't need the full provider block every time.

### Examples (Standard Mode)

**Research workflow:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching OAuth authentication patterns

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and community research
🔵 Claude - Strategic synthesis
```

**Build workflow:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
🛠️ Develop Phase: Building user authentication system

Providers:
🔴 Codex CLI - Code generation and patterns
🟡 Gemini CLI - Alternative approaches
🔵 Claude - Integration and quality gates
```

**Review workflow:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation mode
✅ Deliver Phase: Reviewing authentication implementation

Providers:
🔴 Codex CLI - Code quality analysis
🟡 Gemini CLI - Security and edge cases
🔵 Claude - Synthesis and recommendations
```

**Debate:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - AI Debate Hub
🐙 Debate: Redis vs Memcached for session storage

Participants:
🔴 Codex CLI - Technical perspective
🟡 Gemini CLI - Ecosystem perspective
🔵 Claude - Moderator and synthesis
```

### During Execution

When showing results from each provider, prefix with their indicator:

```
🔴 **Codex Analysis:**
[Codex findings...]

🟡 **Gemini Analysis:**
[Gemini findings...]

🔵 **Claude Synthesis:**
[Your synthesis...]
```

### Why This Matters

Users need to understand:
1. **What's running** - Which AI providers are being invoked
2. **Cost implications** - External CLIs (🔴 🟡) use their API keys and cost money
3. **Progress tracking** - Which phase of the workflow is active

Without indicators, users have no visibility into what's happening or what they're paying for.

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

Before running workflows, check provider availability:
- Codex CLI: `command -v codex` or check for OPENAI_API_KEY
- Gemini CLI: `command -v gemini` or check for GEMINI_API_KEY
- Antigravity CLI: `command -v agy`
- Perplexity: check for PERPLEXITY_API_KEY (API-only, no CLI needed)
- OpenRouter: check for OPENROUTER_API_KEY
- Ollama: `command -v ollama` + server health at http://localhost:11434
- Copilot CLI: `command -v copilot` + auth (COPILOT_GITHUB_TOKEN or gh CLI)
- Qwen CLI: `command -v qwen` + auth (~/.qwen/oauth_creds.json or QWEN_API_KEY)
- OpenCode CLI: `command -v opencode` + auth (`opencode auth list` exit code)

If a provider is unavailable, note it in the banner:
```
Providers:
🔴 Codex CLI - [role] (unavailable - skipping)
🟡 Gemini CLI - [role]
🔵 Claude - [role]
```

---

## Cost Awareness

Always be mindful that external CLIs cost money:
- 🔴 Codex: ~$0.01-0.30 per query depending on model (GPT-5.5 $5/$30 MTok — premium default as of v9.44, GPT-5.4 $2.50/$15, GPT-5.3-Codex $1.75/$14, Mini $0.25/$2.00 MTok)
- 🟡 Gemini: ~$0.01-0.03 per query (Gemini 3.1 Pro Preview $2.50/$10 MTok, 3 Flash Preview $0.25/$1)
- 🧭 Antigravity CLI (`agy`): Included with the user's Antigravity access/subscription; backend cost depends on selected `OCTOPUS_AGY_MODEL`. Because Antigravity's model list is service-owned, explicit pins should use labels returned by `agy models` (for example `Gemini 3.5 Flash (Low)`) or `default`/`agy/default` to use the CLI default.
- 🟣 Perplexity: ~$0.01-0.05 per query (Sonar Pro $3/$15 MTok, Sonar $1/$1 MTok)
- 🔵 Claude (Sonnet 4.6): Included with Claude Code subscription
- 🔵 Claude (Fable 5, Mythos-class, opt-in via `OCTOPUS_OPUS_MODEL=claude-fable-5`): **$10/$50 per MTok** — 2x Opus 4.8 cost. 1M context, 128K output. Never auto-selected. Note: Anthropic retains prompts/outputs up to 30 days for safety classifiers.
- 🔵 Claude (Opus 4.8, default when `SUPPORTS_OPUS_4_8=true`): $5/$25 per MTok input/output. 1M context native. Use `high` effort by default; use `xhigh` for hard implementation, deep review, and long-running asynchronous workflows.
- 🔵 Claude (Opus 4.8 Fast): $10/$50 per MTok — 2x standard cost for roughly 2.5x output speed. Use only when latency matters.
- 🔵 Claude (Opus 4.7, legacy/current-minus-one): $5/$25 per MTok input/output. Used automatically on Claude Code versions before 2.1.154 when supported.
- 🔵 Claude (Opus 4.6, legacy): $5/$25 per MTok — still selectable via `OCTOPUS_OPUS_MODEL=claude-opus-4.6` or `claude-opus-legacy` agent type
- 🔵 Claude (Opus 4.6 Fast, legacy): **$30/$150 per MTok** (6x standard) — lower latency, extra-usage billing for pinned 4.6 sessions.
- 🟤 OpenCode: Variable cost — free for native models, uses backend provider pricing when routing to OpenAI/Google

Note: Some OpenAI models (o-series reasoning, gpt-4.1, gpt-5.4-pro, gpt-5.5-pro) require API keys and are NOT available via ChatGPT subscription/OAuth auth.

For simple tasks that don't need multi-AI perspectives, suggest using Claude directly without orchestration.

### Opus 4.8 Effort Levels (Claude Code v2.1.154+)

Opus 4.8 defaults to `high` effort across Claude Code and the API. Claude Code still supports `xhigh` between `high` and `max`; the plugin reserves it for work that benefits from deeper reasoning:

- **probe / discover** — `high`
- **grasp / define** — `high`, or `xhigh` for explicitly complex planning
- **tangle / develop** — `xhigh` for complex implementation, `high` otherwise
- **ink / deliver** — `xhigh` for security/architecture/deep review, `high` otherwise

`xhigh` falls back to `high` on older models where Claude Code does not expose it. Override per-session with `OCTOPUS_EFFORT_OVERRIDE=low|medium|high|xhigh|max`.

### Fast Opus Mode

Fast mode is a latency control, not a reasoning-effort control. On Opus 4.8 it costs $10/$50 per MTok (2x standard) and should be used only when a human is actively waiting. Legacy Opus 4.6 fast remains much more expensive at $30/$150 per MTok.

When `SUPPORTS_FAST_OPUS=true` is detected, orchestrate.sh routes conservatively:
- **Default: Opus 4.8 standard** for all multi-phase workflows (embrace, discover, develop, etc.)
- **Fast mode: only** for interactive single-shot Opus queries where the user is actively waiting and latency matters
- **Never fast in autonomous/background mode** (no human waiting = no latency benefit)
- **User override**: Set `OCTOPUS_OPUS_MODE=fast` to force fast mode when supported
- **User override**: Set `OCTOPUS_OPUS_MODE=standard` to force standard Opus everywhere (default behavior)
- **User override**: Set `OCTOPUS_OPUS_MODEL=claude-opus-4.6` to pin legacy 4.6 standard across the board

Always warn users about the cost difference before enabling fast mode.

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


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

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
