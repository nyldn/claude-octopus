---
command: octo:discover
description: "Discovery phase - Multi-AI research and exploration"
aliases:
  - probe
  - research-phase
---

# Discover - Discovery Phase 🔍

**Part of Double Diamond: DISCOVER** (divergent thinking)

Multi-perspective research using external CLI providers.

## Usage

```bash
/octo:discover       # Discovery phase
```

## Natural Language Examples

Just describe what you want to research:

```
"Research OAuth authentication patterns"
"Explore caching strategies for high-traffic APIs"
"Investigate microservices best practices"
"What are the options for real-time data sync?"
```

## What This Phase Does

The **discover** phase executes multi-perspective research using external CLI providers:

1. **🔴 Codex CLI** - Technical implementation analysis, code patterns, framework specifics
2. **🟡 Gemini CLI** - Broad ecosystem research, community insights, alternative approaches
3. **🔵 Claude (You)** - Strategic synthesis and recommendation

This is the **divergent** phase - we cast a wide net to explore all possibilities before narrowing down.

## When to Use Discover

Use discover when you need:
- **Research**: "What are authentication best practices in 2025?"
- **Exploration**: "What are the different caching strategies available?"
- **Options Analysis**: "What libraries can I use for date handling?"
- **Comparative Research**: "Compare Redis vs Memcached for session storage"
- **Ecosystem Understanding**: "What's the state of React server components?"
- **Pattern Discovery**: "What are common API pagination patterns?"

**Don't use discover for:**
- Reading files in the current project (use Read tool)
- Questions about specific implementation details (use code review)
- Quick factual questions Claude knows (no need for multi-provider)

## Part of the Full Workflow

Discover is phase 1 of 4 in the embrace (full) workflow:
1. **Discover** ← You are here
2. Define
3. Develop
4. Deliver

To run all 4 phases: `/octo:embrace`
