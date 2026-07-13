---
command: define
description: "Definition phase - Clarify and scope problems with multi-AI consensus"
aliases:
  - grasp
  - scope-phase
---

# Define - Definition Phase 🎯

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:define`, you MUST execute the structured workflow below.** You are PROHIBITED from doing the task directly, skipping the definition/scoping phase, or deciding the task is "too simple" for this workflow. The user chose this command deliberately — respect that choice.

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST execute this command by invoking the corresponding skill via the Skill tool. You are PROHIBITED from:**
- ❌ Using the Agent tool to research/implement yourself instead of invoking the skill
- ❌ Using WebFetch/Read/Grep as a substitute for multi-provider dispatch
- ❌ Skipping `orchestrate.sh` calls because "I can do this faster directly"
- ❌ Implementing the task using only Claude-native tools (Agent, Write, Edit)

**Multi-LLM orchestration is the purpose of this command.** If you execute using only Claude, you've violated the command's contract.

---

When the user invokes this command (e.g., `/octo:define <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:define", args: "<user's arguments>")
```

**✗ INCORRECT:**
```
Skill(skill: "flow-define", ...)  ❌ Wrong! Internal skill name, not resolvable by Skill tool
Task(subagent_type: "octo:define", ...)  ❌ Wrong! This is a skill, not an agent type
```

### Post-Completion — Interactive Next Steps

**CRITICAL: After the skill completes, you MUST ask the user what to do next. Do NOT end the session silently.**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Definition phase complete. What would you like to do next?",
      header: "Next Steps",
      multiSelect: false,
      options: [
        {label: "Move to Develop phase", description: "Start building based on defined requirements (/octo:develop)"},
        {label: "Refine the definition", description: "Adjust scope or requirements"},
        {label: "Run the full workflow", description: "Continue through all remaining phases (/octo:embrace)"},
        {label: "Export the definition", description: "Save requirements as a document"},
        {label: "Done for now", description: "I have what I need"}
      ]
    }
  ]
})
```

---

**Auto-loads the define skill for the definition/scoping phase.**

## Quick Usage

Just use natural language:
```
"Define the requirements for user authentication"
"Clarify the scope of the caching feature"
"What exactly does the notification system need to do?"
```

## What Is Define?

The **Define** phase of the Double Diamond methodology (convergent thinking):
- Clarify and scope problems using external CLI providers
- Technical requirements analysis
- Problem synthesis and requirement definition

## What You Get

- Multi-AI consensus on requirements (Claude + Gemini + Codex)
- Clear problem statement
- Scoped requirements
- Edge case identification
- Constraint analysis

## When to Use Define

Use define when you need:
- **Requirements**: "Define the requirements for X"
- **Clarification**: "Clarify the scope of Y"
- **Scoping**: "What exactly does X need to do?"
- **Problem Understanding**: "Help me understand the problem with Y"

## Part of the Full Workflow

Define is phase 2 of 4 in the embrace (full) workflow:
1. Discover
2. **Define** <- You are here
3. Develop
4. Deliver

To run all 4 phases: `/octo:embrace`
