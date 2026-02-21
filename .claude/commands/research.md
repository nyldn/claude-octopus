---
command: research
description: Deep research with multi-source synthesis and comprehensive analysis
---

# Research - Deep Multi-AI Research

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:research <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:discover", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:discover", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `flow-discover` skill for multi-AI research. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `flow-discover` skill for comprehensive research tasks.**

## Quick Usage

Just use natural language:
```
"Research OAuth 2.0 authentication patterns"
"Deep research on microservices architecture best practices"
"Research the trade-offs between Redis and Memcached"
```

## What Is Research?

An alias for the **Discover** phase of the Double Diamond methodology:
- Multi-AI research (Claude + Gemini + Codex)
- Comprehensive analysis of options
- Trade-off evaluation
- Best practice identification

## Natural Language Examples

```
"Research GraphQL vs REST API design patterns"
"I need deep research on Kubernetes security best practices"
"Research authentication strategies for microservices"
```
