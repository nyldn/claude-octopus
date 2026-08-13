---
command: spec
disable-model-invocation: true
description: "NLSpec authoring - Structured specification from multi-AI research"
aliases:
  - nlspec
  - specification
---

# Spec - NLSpec Authoring

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:spec <arguments>`):

**CORRECT - Read the explicit workflow source:**
```
Read ${HOME}/.claude-octopus/plugin/.claude/skills/flow-spec/SKILL.md, then execute it with <user's arguments>
```

**INCORRECT:**
```
Skill(skill: "flow-spec", ...)  ❌ Wrong! Octopus skills are model-invocation disabled
Task(subagent_type: "octo:spec", ...)  ❌ Wrong! This is a skill, not an agent type
```

---

**Auto-loads the spec skill for NLSpec authoring.**

## Quick Usage

Just describe what you want to specify:
```
"Specify a user authentication system"
"Create a spec for real-time chat"
"Define requirements for payment processing"
```

## What Is Spec?

NLSpec (Natural Language Specification) authoring:
- Structured specification from multi-AI research
- Question-first approach to understand scope
- Probe-based research for domain context
- Validated completeness checking

## What You Get

- Multi-AI research (Claude + Antigravity + Codex) on the domain
- Structured NLSpec with behaviors, actors, constraints
- Adversarial completeness challenge from a second provider (surfaces missing requirements and overlooked edge cases)
- Completeness validation with scoring
- Saved specification file for downstream workflows

## When To Use

- Starting a new project from scratch
- Defining requirements before implementation
- Creating a specification for handoff
- Establishing acceptance criteria upfront

## Natural Language Examples

```
"Specify an OAuth 2.0 authentication system"
"Create a spec for a REST API gateway"
"Define the requirements for a CI/CD pipeline"
```
