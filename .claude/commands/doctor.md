---
command: doctor
description: Environment diagnostics — check providers, auth, config, hooks, scheduler, and more
---

# Doctor - Environment Diagnostics

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:doctor <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:doctor", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:doctor", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `skill-doctor` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `skill-doctor` skill for environment health checks.**

## Quick Usage

Just use natural language:
```
"Run doctor"
"Check my setup"
"Is everything working?"
"Why isn't octopus working?"
```

## What It Checks

- Provider availability (Claude, Codex, Gemini)
- Authentication and API keys
- Plugin configuration
- Hook registration
- Scheduler status
- File permissions and paths

## Natural Language Examples

```
"Run a health check"
"Check if my providers are configured"
"Diagnose my octopus setup"
```
