---
description: "Generate slide deck presentations from briefs or research"
disable-model-invocation: true
---

# Deck - Slide Deck Generator

**Your first output line MUST be:** `🐙 Octopus Deck Generator`

## Instructions

Read and follow the full skill instructions from:
`${HOME}/.claude-octopus/plugin/.claude/skills/skill-deck/SKILL.md`

## Quick Usage

Just describe what you need:
```
"Create a pitch deck for our Series A"
"Build a 10-slide project update for leadership"
"Make a technical presentation about our API architecture"
```

## Pipeline

1. **Brief** — Clarify audience, slide count, and tone
2. **Research** — Optional context gathering (or bring your own content)
3. **Outline** — Slide-by-slide structure for your approval
4. **Render** — Use the selected presentation skill and optional house template

## Tips

- Provide as much context upfront to skip clarification questions
- Run `/octo:discover [topic]` first for research-heavy presentations
- The outline step lets you reshape the deck before rendering
- Uses any suitable advertised renderer, including a standalone `pptx` skill
- Name a renderer and template in the request, or save them in
  `~/.claude-octopus/document-renderers.json`. See `docs/DOCUMENT-RENDERERS.md`
  in the installed Octopus root.

## Examples

```
/octo:deck investor pitch for AI-powered logistics startup
/octo:deck quarterly business review for engineering leadership
/octo:deck technical deep-dive on our microservices migration
```
