---
command: spec
description: "NLSpec authoring - Structured specification from multi-AI research"
aliases:
  - nlspec
  - specification
---

# Spec - NLSpec Authoring

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:spec <arguments>`):

**CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:spec", args: "<user's arguments>")
```

**INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:spec", ...)  -- Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `flow-spec` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `flow-spec` skill for NLSpec authoring.**

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

- Multi-AI research (Claude + Gemini + Codex) on the domain
- Structured NLSpec with behaviors, actors, constraints
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
