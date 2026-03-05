---
command: probe
description: Research and discovery phase - Multi-AI research with broad exploration
---

# Probe - Discovery Phase (Double Diamond)

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:probe <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:probe", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:probe", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `flow-discover` skill (alias: `probe`). Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `flow-discover` skill for the research/discovery phase.**

## Quick Usage

Just use natural language:
```
"Research authentication patterns"
"Probe microservices architecture approaches"
"Explore caching strategies"
```

## What Is Probe?

The **Discover** phase of the Double Diamond methodology:
- Divergent thinking
- Broad exploration
- Multi-perspective research
- Problem space understanding

## What You Get

- Multi-AI research (Claude + Gemini + Codex)
- Comprehensive analysis of options
- Trade-off evaluation
- Best practice identification
- Implementation considerations

## When To Use

- Starting a new feature
- Researching technologies
- Exploring design patterns
- Understanding problem space
- Gathering requirements

## Natural Language Examples

```
"Research OAuth 2.0 vs JWT authentication"
"Probe database options for our use case"
"Explore state management patterns for React"
```
