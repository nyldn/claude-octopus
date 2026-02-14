---
command: deck
description: Generate slide deck presentations from briefs or research
---

# Deck - Slide Deck Generator

## Instructions for Claude

When the user invokes this command (e.g., `/octo:deck <arguments>`):

**Use the Skill tool:**
```text
Skill(skill: "octo:deck", args: "<user's arguments>")
```

**Do NOT use Task tool** — this is a skill, not an agent type.

---

**Auto-loads the `skill-deck` skill for slide deck generation with outline approval.**

## Quick Usage

Just describe what you need:
```text
"Create a pitch deck for our Series A"
"Build a 10-slide project update for leadership"
"Make a technical presentation about our API architecture"
```

## Pipeline

1. **Brief** — Clarify audience, slide count, and tone
2. **Research** — Optional context gathering (or bring your own content)
3. **Outline** — Slide-by-slide structure for your approval
4. **PPTX** — Rendered PowerPoint file via document-skills

## Tips

- Provide as much context upfront to skip clarification questions
- Run `/octo:discover [topic]` first for research-heavy presentations
- The outline step lets you reshape the deck before rendering
- Works best with `document-skills` plugin installed

## Examples

```text
/octo:deck investor pitch for AI-powered logistics startup
/octo:deck quarterly business review for engineering leadership
/octo:deck technical deep-dive on our microservices migration
```
