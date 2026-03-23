---
name: skill-context-detection
version: 1.0.0
description: "Auto-detect whether the user is in a Development (code) or Knowledge (research/strategy) context to tailor workflow behavior, agent selection, and output format. Use when: any workflow skill activates and needs to determine context, user asks about current mode, or context-aware routing is needed."
---

# Context Detection - Internal Skill

Auto-detects Dev vs Knowledge context to replace manual `/octo:km` toggling. Used internally by workflow skills.

## Detection Algorithm

### Step 1: Check for Explicit Override

```bash
if [[ -f ~/.claude-octopus/config/knowledge-mode ]]; then
  EXPLICIT_MODE=$(cat ~/.claude-octopus/config/knowledge-mode)
  # "on" = knowledge, "off" = dev, "auto" = proceed to auto-detection
fi
```

### Step 2: Analyze Prompt Content (Strongest Signal)

**Knowledge indicators**: "market", "ROI", "stakeholders", "strategy", "personas", "presentation", "report", "PRD", "literature", "synthesis"

**Dev indicators**: "API", "endpoint", "database", "function", "implement", "debug", "refactor", "test", "deploy", "code", "migration"

Score by counting matches. Higher count wins. If tied, check project context.

### Step 3: Analyze Project Context (Secondary Signal)

- **Dev**: Has `package.json`, `Cargo.toml`, `go.mod`; has `src/`, `lib/`, `app/` with code files
- **Knowledge**: Has `docs/`, `research/`, `strategy/`; mostly `.md`, `.docx`, `.pdf` files

### Step 4: Default Fallback

- Git repo with code files: **Dev Context**
- No code files: **Knowledge Context**

## Output Format

```json
{
  "context": "dev" | "knowledge",
  "confidence": "high" | "medium" | "low",
  "signals": { "prompt_indicators": [...], "project_type": "...", "explicit_override": false }
}
```

## Context Behavior by Workflow

| Workflow | Dev Context | Knowledge Context |
|----------|-------------|-------------------|
| **Discover** | Technical implementation, library comparison | Market analysis, academic synthesis |
| **Develop** | Code generation, tests, architecture | PRDs, strategy docs, presentations |
| **Deliver** | Code quality, security, OWASP | Document quality, argument strength |
| **Agents** | codex, backend-architect, code-reviewer | strategy-analyst, ux-researcher, exec-communicator |

## Override Commands

| Command | Effect |
|---------|--------|
| `/octo:km on` | Force Knowledge Context |
| `/octo:km off` | Force Dev Context |
| `/octo:km auto` | Return to auto-detection |
| `/octo:km` | Show current status |

## Confidence Levels

- **High**: Prompt AND project context signals agree
- **Medium**: Only one signal source detected
- **Low**: Ambiguous; mention detected context to user for confirmation

## Proactive Skill Suggestions

Surface relevant commands based on detected work stage:

| Detected Context | Suggestion |
|-----------------|------------|
| Brainstorming | `/octo:brainstorm` |
| Debugging | `/octo:debug` |
| Testing | `/octo:tdd` |
| Code review | `/octo:review` |
| Ready to ship | `/octo:deliver` |
| Researching | `/octo:research` |
| Security work | `/octo:security` |

Opt-out via "stop suggesting" (sets `OCTO_PROACTIVE_SUGGESTIONS=off` in preferences). Re-enable via "be proactive" or "turn on tips".

### Detection Signals

- Recent tool usage patterns (many Bash calls = implementing/debugging)
- File types being edited (.test.ts = testing, .md = documentation)
- Error patterns in output (stack traces = debugging)
- Git state (uncommitted changes = implementing, clean tree = review/ship)
