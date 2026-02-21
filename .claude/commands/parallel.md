---
command: parallel
description: "Team of Teams - Decompose compound tasks across independent claude instances"
aliases:
  - team
  - teams
---

# Parallel - Team of Teams

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:parallel <arguments>`):

**CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:parallel", args: "<user's arguments>")
```

**INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:parallel", ...)  -- Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `flow-parallel` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `flow-parallel` skill for Team of Teams orchestration.**

## Quick Usage

Describe the compound task you want decomposed:
```
"Build a full authentication system with OAuth, RBAC, and audit logging"
"Create a complete e-commerce platform with payments, inventory, and shipping"
"Implement CI/CD pipeline with testing, linting, and deployment stages"
```

## What Is Parallel?

**Team of Teams** orchestration — decomposes compound tasks into independent work packages and delegates each to a separate `claude -p` process. Each process loads the full Octopus plugin, giving every work package its own Double Diamond, agents, and quality gates.

Key architectural distinction: Task tool subagents don't load plugins. Independent `claude -p` processes do.

## What You Get

- Work Breakdown Structure (WBS) decomposition
- Independent `claude -p` processes per work package
- Full plugin capabilities in each worker
- Parallel execution with staggered launch
- Aggregated results with exit code verification

## When To Use

- Compound tasks with 3+ independent components
- Tasks that would benefit from parallel execution
- Projects where each component needs full AI capabilities
- When you want isolated, non-interfering work streams

## Natural Language Examples

```
"Parallel build auth system with OAuth, sessions, and RBAC"
"Team up on building a dashboard with charts, filters, and export"
"Decompose and parallelize the API migration across 5 services"
```
