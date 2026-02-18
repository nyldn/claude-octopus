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
| 🔵 | Claude subagent processing | Included with Claude Code |

### When to Display Indicators

Display indicators when:
- Invoking any `/octo:` command
- Running `orchestrate.sh` with any workflow (probe, grasp, tangle, ink, embrace, etc.)
- User triggers workflow with "octo" prefix ("octo research X", "octo build Y")
- Executing multi-provider operations

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

### Examples

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
- 🔴 Codex: ~$0.01-0.15 per query depending on model (GPT-5.3-Codex $1.75/$14 MTok, Spark 15x faster, Mini ~$0.30/$1.25 MTok)
- 🟡 Gemini: ~$0.01-0.03 per query (Gemini Pro)
- 🔵 Claude (Sonnet 4.6): Included with Claude Code subscription
- 🔵 Claude (Opus 4.6): $5/$25 per MTok input/output when using `claude-opus` agent type
- 🔵 Claude (Opus 4.6 Fast): **$30/$150 per MTok** (6x standard) - lower latency, extra-usage billing (v2.1.36+)

For simple tasks that don't need multi-AI perspectives, suggest using Claude directly without orchestration.

### Fast Opus 4.6 Mode (Claude Code v2.1.36+)

**WARNING: Fast Opus is 6x more expensive than standard Opus.** It uses extra-usage billing at $30/$150 per MTok (vs $5/$25 standard). It provides lower latency but identical quality.

When `SUPPORTS_FAST_OPUS=true` is detected, orchestrate.sh routes conservatively:
- **Default: standard mode** for all multi-phase workflows (embrace, discover, develop, etc.)
- **Fast mode only** for interactive single-shot Opus queries where the user is actively waiting
- **Never fast in autonomous/background mode** (no human waiting = no latency benefit)
- **User override**: Set `OCTOPUS_OPUS_MODE=fast` to force fast everywhere (costly!)
- **User override**: Set `OCTOPUS_OPUS_MODE=standard` to force standard everywhere (default behavior)

Always warn users about the cost difference before enabling fast mode.

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

## Enforcement Best Practices (Mandatory for Workflow Skills)

Skills that invoke orchestrate.sh MUST use the **Validation Gate Pattern** to ensure proper execution.

### Required Pattern

1. **Add to frontmatter:**
   ```yaml
   execution_mode: enforced
   pre_execution_contract:
     - interactive_questions_answered
     - visual_indicators_displayed
   validation_gates:
     - orchestrate_sh_executed
     - synthesis_file_exists
   ```

2. **Add EXECUTION CONTRACT section** with:
   - Blocking steps (numbered, mandatory)
   - Explicit Bash tool calls (not just markdown examples)
   - Validation gates that verify execution
   - Clear prohibition statements (what NOT to do)

3. **Use imperative language:**
   - ✅ "You MUST execute..."
   - ✅ "PROHIBITED from..."
   - ✅ "CANNOT SKIP..."
   - ❌ "You should execute..."
   - ❌ "It's recommended to..."
   - ❌ "Consider calling..."

4. **Validate artifacts:**
   - Check synthesis files exist and are recent
   - Verify via filesystem checks, not assumptions
   - Fail explicitly if validation doesn't pass

### Example: skill-deep-research.md

See `.claude/skills/skill-deep-research.md` for reference implementation of the Validation Gate Pattern.

All future orchestrate.sh-based skills should follow this pattern.

---

## Modular Configuration (Claude Code v2.1.20+)

Claude Octopus uses a modular CLAUDE.md structure for better organization and context management.

### Directory Structure

```
claude-octopus/
├── CLAUDE.md                    # Main instructions (this file)
├── config/
│   ├── providers/
│   │   ├── codex/CLAUDE.md     # Codex-specific instructions
│   │   ├── gemini/CLAUDE.md    # Gemini-specific instructions
│   │   └── claude/CLAUDE.md    # Claude-specific instructions
│   └── workflows/CLAUDE.md      # Double Diamond methodology
```

### Loading Additional Context

Use `--add-dir` flag to load specific configuration modules:

**Load provider-specific context:**
```bash
claude --add-dir=config/providers/codex    # When working with Codex
claude --add-dir=config/providers/gemini   # When working with Gemini
```

**Load workflow methodology:**
```bash
claude --add-dir=config/workflows  # Load Double Diamond instructions
```

**Load multiple modules:**
```bash
claude \
  --add-dir=config/providers/codex \
  --add-dir=config/providers/gemini \
  --add-dir=config/workflows
```

### Benefits of Modular Configuration

1. **Reduced Context Pollution** - Load only what's needed
2. **Environment-Specific** - Different configs for different scenarios
3. **Maintainability** - Update provider configs independently
4. **Clarity** - Separate concerns (providers vs workflows vs core)

### When to Load Each Module

| Module | When to Load |
|--------|--------------|
| `providers/codex` | Working specifically with Codex CLI integration |
| `providers/gemini` | Working specifically with Gemini CLI integration |
| `providers/claude` | Understanding Claude's orchestrator role |
| `workflows` | Learning about Double Diamond methodology |

### Note

The main `CLAUDE.md` (this file) contains essential visual indicators and workflow triggers that are **always loaded** by default.
