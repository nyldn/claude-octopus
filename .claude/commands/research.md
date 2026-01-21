---
command: research
description: Deep research with multi-source synthesis and comprehensive analysis
---

# Research - Deep Research Skill

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:research <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:research", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:research", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `skill-deep-research` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `skill-deep-research` skill for comprehensive research tasks.**

## Quick Usage

Just use natural language:
```
"Research OAuth 2.0 authentication patterns"
"Deep research on microservices architecture best practices"
"Research the trade-offs between Redis and Memcached"
```

## What You Get

- Multi-source synthesis (academic papers, documentation, community discussions)
- Comparative analysis of different approaches
- Pros/cons evaluation
- Best practice recommendations
- Implementation considerations

## Research Depth

The skill automatically adapts to your needs:
- **Quick**: Fast overview of key concepts
- **Standard**: Comprehensive analysis with examples
- **Deep**: Thorough research with citations and evidence

## Natural Language Examples

```
"Research GraphQL vs REST API design patterns"
"I need deep research on Kubernetes security best practices"
"Research authentication strategies for microservices"
```
