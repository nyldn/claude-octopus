# Visual Indicators Guide

Claude Octopus uses **visual indicators** (emojis) to show you exactly which AI provider is responding at any given moment. This helps you understand whether you're using external CLI tools (which cost money and use your API quotas) or built-in Claude Code capabilities.

## The Indicator System

| Indicator | Meaning | Provider | Cost |
|-----------|---------|----------|------|
| 🐙 | **Parallel Mode** | Multiple CLIs orchestrated | Uses external APIs |
| 🔴 | **Codex CLI** | OpenAI Codex | Your OPENAI_API_KEY |
| 🟡 | **Gemini CLI** | Google Gemini | Your GEMINI_API_KEY |
| 🔵 | **Claude Subagent** | Claude Code Task tool | Included with Claude Code |

---

## What Triggers External CLIs

External CLI providers (Codex and Gemini) are invoked when you:

### 1. Use Explicit Commands
```
/parallel-agents "research OAuth patterns"
/debate "Should we use Redis or Memcached?"
```

### 2. Trigger Workflow Skills

Natural language that triggers orchestrate.sh workflows:

- **Probe (Research)**: "research X", "explore Y", "investigate Z"
- **Grasp (Define)**: "define requirements for X", "clarify scope of Y"
- **Tangle (Build)**: "build X", "implement Y", "create Z"
- **Ink (Review)**: "review X", "validate Y", "test Z"

### 3. Enable Knowledge Mode

When Knowledge Mode is ON, research tasks use external CLIs:

```
/octo:km on
"Research market opportunities in healthcare"
```

### 4. Use Direct CLI Commands

```bash
# Direct orchestrate.sh execution
./scripts/orchestrate.sh probe "research GraphQL vs REST"
./scripts/orchestrate.sh tangle "implement user authentication"

# Direct CLI execution
codex exec "Generate API endpoint for users"
gemini -y "What are authentication best practices?"
```

---

## What Triggers Claude Subagents

Claude subagents (built-in Claude Code Task tool) are used when:

### Simple Operations
- Reading files: "read src/auth.ts"
- Writing code: "add a comment to this function"
- Editing files: "fix this typo"
- File searches: "find all TypeScript files"

### Git and Bash Operations
- Git commands: "show git status", "create a commit"
- Terminal commands: "run npm install"
- File operations: "list files in this directory"

### Code Navigation
- "What files handle authentication?"
- "Show me the database models"
- "Find where the API routes are defined"

### Single-Perspective Tasks
Tasks that don't benefit from multiple AI perspectives:
- Simple bug fixes
- Documentation updates
- Code formatting
- Basic refactoring

---

## Why This Matters

### Cost Implications

**External CLIs use your API quotas:**
- 🔴 Codex CLI: OpenAI API costs (GPT-5.x based)
- 🟡 Gemini CLI: Google AI costs (Gemini 3.0)
- Typical costs: $0.01-0.10 per query

**Claude subagents are included:**
- 🔵 Claude Code Task tool: No additional cost
- Included with your Claude Code subscription

### When to Use Each

**Use External CLIs (🐙 🔴 🟡) when:**
- You need multiple perspectives on a problem
- Research requires broad coverage (ecosystem analysis)
- Complex implementation needs different approaches
- Security review benefits from adversarial analysis
- You're working on high-stakes decisions

**Use Claude Subagents (🔵) when:**
- Simple file operations suffice
- Single perspective is adequate
- Quick edits or fixes needed
- Cost efficiency is important
- Task is straightforward

---

## Visual Indicator Examples

### Example 1: Research Task (External CLIs)

```
User: Research authentication best practices for React apps

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Probe Phase: Researching authentication patterns

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and community research
🔵 Claude - Strategic synthesis

[Executes orchestrate.sh probe...]

# Research Findings: Authentication Best Practices

Based on multi-provider analysis...
[Synthesized results from all three providers]
```

### Example 2: Simple File Read (Claude Subagent)

```
User: Read the auth.ts file and explain what it does

Claude:
[No visual indicators - uses built-in Read tool]

Here's what auth.ts does:
[Explanation based on file contents]
```

### Example 3: Implementation Task (External CLIs)

```
User: Build a user authentication system with JWT

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation
🛠️ Tangle Phase: Building authentication system

Providers:
🔴 Codex CLI - Code generation and patterns
🟡 Gemini CLI - Alternative approaches
🔵 Claude - Integration and refinement

[Executes orchestrate.sh tangle...]

# Implementation Plan: User Authentication System
[Synthesized approach from all providers]
```

### Example 4: Code Review (External CLIs)

```
User: Review my authentication code for security issues

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation
✅ Ink Phase: Reviewing authentication implementation

Providers:
🔴 Codex CLI - Code quality and best practices
🟡 Gemini CLI - Security audit and edge cases
🔵 Claude - Synthesis and validation report

[Executes orchestrate.sh ink...]

# Validation Report: Authentication Implementation
Overall Status: ⚠️ PASSED WITH WARNINGS
Quality Score: 78/100
[Detailed findings from all providers]
```

---

## Workflow Visual Indicators

Each Double Diamond workflow phase has its own visual identity:

### 🔍 Probe (Discover)
```
🐙 **CLAUDE OCTOPUS ACTIVATED**
🔍 Probe Phase: Research and exploration mode
```
- **Purpose**: Broad research, option discovery
- **Providers**: All three (Codex, Gemini, Claude)
- **Output**: Synthesis of multiple perspectives

### 🎯 Grasp (Define)
```
🐙 **CLAUDE OCTOPUS ACTIVATED**
🎯 Grasp Phase: Clarifying requirements and scope
```
- **Purpose**: Narrow down to specific requirements
- **Providers**: All three (technical + business perspectives)
- **Output**: Clear problem definition

### 🛠️ Tangle (Develop)
```
🐙 **CLAUDE OCTOPUS ACTIVATED**
🛠️ Tangle Phase: Building and developing solutions
```
- **Purpose**: Generate multiple implementation approaches
- **Providers**: All three (different coding styles)
- **Output**: Implementation plan with quality gates

### ✅ Ink (Deliver)
```
🐙 **CLAUDE OCTOPUS ACTIVATED**
✅ Ink Phase: Reviewing and validating implementation
```
- **Purpose**: Quality assurance before delivery
- **Providers**: All three (quality, security, completeness)
- **Output**: Validation report with go/no-go decision

---

## Debugging: No Visual Indicators?

If you're not seeing visual indicators when you expect them:

### Check 1: Plugin Installation
```
/plugin list
```
Look for `claude-octopus@nyldn-plugins` in the installed list.

### Check 2: Provider Configuration
```
/octo:setup
```
Verify that Codex and/or Gemini CLIs are installed.

### Check 3: Hook Configuration

The visual indicators are injected via PreToolUse hooks. Verify:

```bash
# Check hooks configuration
cat .claude-plugin/hooks.json

# Should contain PreToolUse hooks for orchestrate.sh
```

### Check 4: Task Type

Remember: Not all tasks trigger external CLIs. Simple operations use Claude subagents without indicators.

**Triggers external CLIs:**
- "research X" → probe workflow
- "build X" → tangle workflow
- "review X" → ink workflow
- "/debate X" → debate skill

**Uses Claude subagent (no indicator):**
- "read file.ts"
- "what does this code do?"
- "show git status"

---

## Advanced: Hook-Based Indicators

Visual indicators are implemented using Claude Code's hook system:

### PreToolUse Hooks

File: `.claude-plugin/hooks.json`

```json
{
  "PreToolUse": [
    {
      "matcher": {
        "tool": "Bash",
        "pattern": "orchestrate\\.sh.*(probe|grasp|tangle|ink)"
      },
      "hooks": [
        {
          "type": "prompt",
          "prompt": "🐙 **CLAUDE OCTOPUS ACTIVATED** - Using external CLI providers"
        }
      ]
    },
    {
      "matcher": {
        "tool": "Bash",
        "pattern": "codex exec"
      },
      "hooks": [
        {
          "type": "prompt",
          "prompt": "🔴 **Codex CLI Executing** - Using your OpenAI API credentials"
        }
      ]
    },
    {
      "matcher": {
        "tool": "Bash",
        "pattern": "gemini -[yr]"
      },
      "hooks": [
        {
          "type": "prompt",
          "prompt": "🟡 **Gemini CLI Executing** - Using your Google API credentials"
        }
      ]
    }
  ]
}
```

These hooks inject context into Claude's prompt whenever orchestrate.sh or CLI commands execute, ensuring you always see what's running.

---

## Summary

| Scenario | Indicator | Provider | Cost |
|----------|-----------|----------|------|
| Research task | 🐙 🔍 | Multi-provider | $0.01-0.05 |
| Build feature | 🐙 🛠️ | Multi-provider | $0.02-0.10 |
| Code review | 🐙 ✅ | Multi-provider | $0.02-0.08 |
| Debate | 🐙 (debate) | Multi-provider | $0.05-0.15 |
| Read file | (none) | Claude only | Included |
| Simple edit | (none) | Claude only | Included |
| Git command | (none) | Claude only | Included |

**Key takeaway**: Visual indicators = External APIs = Costs money but provides multi-AI collaboration. No indicators = Claude only = Included with Claude Code.

---

For more information:
- [Triggers Guide](./TRIGGERS.md) - What activates each workflow
- [CLI Reference](./CLI-REFERENCE.md) - Direct CLI usage
- [Plugin Architecture](./PLUGIN-ARCHITECTURE.md) - How it all works
