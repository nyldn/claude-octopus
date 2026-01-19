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
- 🔴 Codex: ~$0.01-0.05 per query (GPT-4 based)
- 🟡 Gemini: ~$0.01-0.03 per query (Gemini Pro)
- 🔵 Claude: Included with Claude Code subscription

For simple tasks that don't need multi-AI perspectives, suggest using Claude directly without orchestration.
