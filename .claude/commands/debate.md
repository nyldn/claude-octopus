---
command: debate
description: AI Debate Hub - Structured three-way debates between Claude, Gemini, and Codex
skill: skill-debate
---

## STOP - DO NOT INVOKE /skill OR Skill() AGAIN

This command is already executing. The `skill-debate` skill has been loaded via frontmatter binding.

---

**Structured multi-AI debates powered by the `skill-debate` skill.**

## Quick Usage

Just use natural language:
```
"Run a debate about whether we should use Redis or PostgreSQL for caching"
"I want Gemini and Codex to debate microservices vs monolith architecture"
"Debate the security implications of our authentication approach"
```

## How It Works

This command activates the AI Debate Hub skill, which:
- Facilitates three-way debates (Claude + Gemini + Codex)
- Provides multiple perspectives on complex decisions
- Includes quality gates and cost tracking
- Exports results to documents

## Debate Styles

- **quick**: Fast, focused analysis (1-2 rounds)
- **thorough**: Deep, comprehensive review (3-5 rounds)
- **adversarial**: Red team vs Blue team security review
- **collaborative**: Consensus-building discussion

## Natural Language Examples

```
"Run a quick debate about Redis vs Memcached"
"I need a thorough debate on our API architecture"
"Adversarial debate on the security of auth.ts"
```

The skill will automatically detect your intent and configure the debate appropriately.
