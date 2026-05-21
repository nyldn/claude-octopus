---
name: skill-knowledge-work
description: "Switch to Knowledge Work mode for research and writing — use when task is non-code focused"
triggerPatterns:
  - "switch.*mode"
  - "knowledge.*mode"
  - "research.*mode"
  - "toggle.*knowledge"
  - "force.*knowledge"
  - "force.*dev"
---

# Knowledge Work Mode - Context Override Skill

## Context Auto-Detection (v7.8+)

**Claude Octopus now auto-detects work context!** The system analyzes your prompt and project to determine whether you're in a **Dev Context** (code-focused) or **Knowledge Context** (research/strategy-focused).

**You typically don't need this skill** - context is detected automatically when you use:
- `octo research X` - Auto-detects dev vs knowledge research
- `octo build X` - Auto-detects code vs document building
- `octo review X` - Auto-detects code vs document review

## When to Use This Override

**Use ONLY when auto-detection is wrong:**
- Auto-detection chose Dev but you want Knowledge behavior
- Auto-detection chose Knowledge but you want Dev behavior
- You want to force a specific context for the entire session

## Override Commands

### Force Knowledge Context
```bash
/octo:km on
```
All subsequent workflows will use Knowledge Context until reset.

### Force Dev Context
```bash
/octo:km off
```
All subsequent workflows will use Dev Context until reset.

### Return to Auto-Detection
```bash
/octo:km auto
```
Context detection returns to automatic mode.

### Check Current Status
```bash
/octo:km
```
Shows current mode (auto, knowledge, or dev).

## How Auto-Detection Works

When you use any `octo` workflow, context is detected by analyzing:

1. **Prompt Content** (strongest signal):
   - Knowledge indicators: "market", "ROI", "stakeholders", "strategy", "personas", "presentation", "report", "PRD"
   - Dev indicators: "API", "endpoint", "database", "implementation", "code", "function", "deploy"

2. **Project Type** (secondary signal):
   - Has `package.json`, `Cargo.toml`, `go.mod` → Dev Context
   - Mostly `.md`, `.docx`, `.pdf` files → Knowledge Context

3. **Explicit Override** (if set via `/octo:km`):
   - Overrides all auto-detection until reset to "auto"

## Visual Indicator Shows Context

When workflows run, you'll see the detected context in the banner:

**Dev Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Dev] Discover Phase: Technical research on caching patterns
```

**Knowledge Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Knowledge] Discover Phase: Market analysis for APAC expansion
```

## Examples of Auto-Detection in Action

### Example 1: Technical Research (Auto → Dev)

**User:** "octo research caching strategies for our Node.js API"

**Claude:** (auto-detects Dev Context from "Node.js API")
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Dev] Discover Phase: Technical research on caching strategies

[Researches with technical/implementation focus]
```

### Example 2: Market Research (Auto → Knowledge)

**User:** "octo research market opportunities in healthcare AI"

**Claude:** (auto-detects Knowledge Context from "market opportunities")
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Knowledge] Discover Phase: Strategic research on healthcare AI market

[Researches with business/strategic focus]
```

### Example 3: Override When Auto Gets It Wrong

**User:** "octo research React patterns"  
**Claude:** (auto-detects Dev) `🔍 [Dev] Discover Phase...`

**User:** "Actually, this is for a presentation. Force knowledge mode."

**Claude:** "Setting context override to Knowledge Mode."
```bash
/octo:km on
```

**User:** "octo research React patterns"  
**Claude:** (uses override) `🔍 [Knowledge] Discover Phase...` (focuses on trends, adoption, strategic implications)

### Example 4: Check Current Status

**User:** "What context mode am I in?"

**Claude:** 
```
Current mode: Auto-detection (no override set)
Last detected context: Dev (based on project having package.json)

To override: /octo:km on (force Knowledge) or /octo:km off (force Dev)
To return to auto: /octo:km auto
```

## What Changes Per Context

### Dev Context 🔧
| Workflow | Focus |
|----------|-------|
| `octo research X` | Technical implementation, libraries, code patterns |
| `octo build X` | Code generation, architecture, tests |
| `octo review X` | Code quality, security, performance |
| Agents | codex, backend-architect, code-reviewer, security-auditor |

### Knowledge Context 🎓
| Workflow | Focus |
|----------|-------|
| `octo research X` | Market analysis, competitive research, literature synthesis |
| `octo build X` | PRDs, strategy docs, presentations, reports |
| `octo review X` | Document quality, argument strength, completeness |
| Agents | strategy-analyst, ux-researcher, exec-communicator, product-writer |

## Document Delivery 📄

After running knowledge workflows, export to professional formats:
- **DOCX** - Word documents for reports, business cases
- **PPTX** - PowerPoint presentations for stakeholder decks
- **XLSX** - Excel spreadsheets for data analysis

Just say: "Export this to Word" or "Create a PowerPoint presentation"

## Override Command Reference

| Command | Description |
|---------|-------------|
| `/octo:km` | Show current status (auto, on, or off) |
| `/octo:km on` | Force Knowledge Context for all workflows |
| `/octo:km off` | Force Dev Context for all workflows |
| `/octo:km auto` | Return to auto-detection (default) |

## When NOT to Use Override

**Don't override if:**
- Auto-detection is working correctly
- You're doing mixed work (let each prompt be detected individually)
- You just want to see what context was detected (check the banner)

**Override is for:**
- Forcing a specific context for an entire session
- Correcting persistent misdetection
- Specific use cases where you know better than auto-detect

## Cross-Task Learnings

At the end of significant work sessions, extract learnings:
1. What task type was this? (debugging, implementation, research, review)
2. What approach worked? What failed?
3. What would you do differently next time?

Store learnings in `.claude-octopus/learnings/<date>-<summary>.json`:
```json
{
  "date": "2026-03-21",
  "task_type": "debugging",
  "approach": "Traced the error from the test failure back to the API handler",
  "outcome": "success",
  "lesson": "Always check middleware ordering before investigating handler logic"
}
```

Each learning file captures: `task_type`, `approach`, `outcome`, and `lesson`.

### Session Start: Relevance Matching

At session start, check for relevant learnings:
- Read `.claude-octopus/learnings/` directory
- Match by task type and file patterns relevant to the current work
- Inject top 3 most relevant learnings as context (within ~5% token budget)
- Prefer recent learnings; deprioritize those older than 30 days

### Budget Controls

- Maximum 5 learnings extracted per session (prevents runaway writes)
- Maximum 50 learning files retained (oldest pruned automatically)
- Relevance injection capped at 3 learnings and ~5% of available token budget
- Learning files are lightweight JSON (~200 bytes each)

## Related Skills

- `/octo:discover` - Research workflow (auto-detects context)
- `/octo:develop` - Build workflow (auto-detects context)
- `/octo:deliver` - Review workflow (auto-detects context)
- `/octo:docs` - Document export (works in both contexts)
