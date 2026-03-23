---
name: skill-knowledge-work
version: 1.0.0
description: "Override auto-detected work context to force Knowledge Work mode (research, strategy, writing) or Dev mode for all subsequent workflows. Use when: user says '/octo:km', 'switch to knowledge mode', 'force dev mode', auto-detection chose the wrong context, or user needs to check current context mode."
---

# Knowledge Work Mode - Context Override Skill

Context is auto-detected for most workflows. This skill is the manual override when auto-detection gets it wrong.

## Override Commands

| Command | Effect |
|---------|--------|
| `/octo:km on` | Force Knowledge Context for all workflows |
| `/octo:km off` | Force Dev Context for all workflows |
| `/octo:km auto` | Return to auto-detection (default) |
| `/octo:km` | Show current status |

## When to Use

**Use ONLY when auto-detection is wrong** -- e.g., it chose Dev but you need Knowledge behavior, or vice versa. Do not use if auto-detection is working correctly or for mixed work (let each prompt be detected individually).

## How Auto-Detection Works

1. **Prompt Content** (strongest signal): Knowledge indicators (market, ROI, strategy, presentation, PRD) vs Dev indicators (API, endpoint, database, implement, deploy)
2. **Project Type** (secondary): `package.json`/`Cargo.toml` = Dev; mostly `.md`/`.docx`/`.pdf` = Knowledge
3. **Explicit Override**: `/octo:km` setting overrides all auto-detection until reset

## Context Behavior Differences

| Workflow | Dev Context | Knowledge Context |
|----------|-------------|-------------------|
| Research | Technical implementation, libraries | Market analysis, competitive research |
| Build | Code generation, architecture, tests | PRDs, strategy docs, presentations |
| Review | Code quality, security, performance | Document quality, argument strength |
| Agents | codex, backend-architect, code-reviewer | strategy-analyst, ux-researcher, product-writer |

## Document Delivery

After knowledge workflows, export to professional formats:
- **DOCX** for reports and business cases
- **PPTX** for stakeholder presentations
- **XLSX** for data analysis

## Cross-Task Learnings

At the end of significant sessions, extract learnings to `.claude-octopus/learnings/<date>-<summary>.json`:

```json
{
  "date": "2026-03-21",
  "task_type": "debugging",
  "approach": "Traced error from test failure to API handler",
  "outcome": "success",
  "lesson": "Check middleware ordering before investigating handler logic"
}
```

At session start, inject top 3 relevant learnings (matched by task type, capped at ~5% token budget). Max 5 learnings per session, 50 files retained total.

## Related Skills

- `/octo:discover` - Research workflow (auto-detects context)
- `/octo:develop` - Build workflow (auto-detects context)
- `/octo:deliver` - Review workflow (auto-detects context)
- `/octo:docs` - Document export (works in both contexts)
