---
command: deliver
description: "Delivery phase - Review, validate, and test with multi-AI quality assurance"
aliases:
  - ink
  - review-phase
---

# Deliver - Delivery Phase ✅

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:deliver`, you MUST execute the structured workflow below.** You are PROHIBITED from doing the task directly, skipping the validation/review phase, or deciding the task is "too simple" for this workflow. The user chose this command deliberately — respect that choice.

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST execute this command by invoking the corresponding skill via the Skill tool. You are PROHIBITED from:**
- ❌ Using the Agent tool to research/implement yourself instead of invoking the skill
- ❌ Using WebFetch/Read/Grep as a substitute for multi-provider dispatch
- ❌ Skipping `orchestrate.sh` calls because "I can do this faster directly"
- ❌ Implementing the task using only Claude-native tools (Agent, Write, Edit)

**Multi-LLM orchestration is the purpose of this command.** If you execute using only Claude, you've violated the command's contract.

---

When the user invokes this command (e.g., `/octo:deliver <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:deliver", args: "<user's arguments>")
```

**✗ INCORRECT:**
```
Skill(skill: "flow-deliver", ...)  ❌ Wrong! Internal skill name, not resolvable by Skill tool
Task(subagent_type: "octo:deliver", ...)  ❌ Wrong! This is a skill, not an agent type
```

### Auto Code Review & E2E Verification (MANDATORY)

**Before presenting results, launch two verification agents in parallel:**

```
Agent(model: "sonnet", subagent_type: "feature-dev:code-reviewer", run_in_background: true,
  description: "Code review: deliver phase",
  prompt: "Review code changes from this session. Check git diff. Report only high-confidence bugs, security issues, and convention violations.")

Agent(model: "sonnet", run_in_background: true,
  description: "E2E test: deliver phase",
  prompt: "Run the project's test suite. Report tests passed/failed and any regressions.")
```

Include findings in the results below. Flag test failures or HIGH-confidence issues prominently.

### Post-Completion — Interactive Next Steps

**CRITICAL: After the skill completes, you MUST present review/test findings AND ask the user what to do next. Do NOT end the session silently.**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Delivery/validation phase complete. What would you like to do next?",
      header: "Next Steps",
      multiSelect: false,
      options: [
        {label: "Address findings", description: "Fix issues identified in the review"},
        {label: "Run another review pass", description: "Re-validate after fixes"},
        {label: "Ship it", description: "Findings are acceptable, proceed to deployment"},
        {label: "Export the review", description: "Save validation results as a document"},
        {label: "Done for now", description: "I have what I need"}
      ]
    }
  ]
})
```

---

**Auto-loads the deliver skill for the validation/review phase.**

## Quick Usage

Just use natural language:
```
"Review the authentication code for security"
"Validate the caching implementation"
"Test the notification system"
```

## What Is Deliver?

The **Deliver** phase of the Double Diamond methodology (convergent thinking):
- Validate and review implementations using external CLI providers
- Security audit and edge case analysis
- Final quality synthesis

## What You Get

- Multi-AI validation (Claude + Gemini + Codex)
- Security audit (OWASP compliance, vulnerability detection)
- Code quality review
- Edge case analysis
- Performance evaluation

## When to Use Deliver

Use deliver when you need:
- **Review**: "Review X" or "Code review Y"
- **Validation**: "Validate Z"
- **Testing**: "Test the implementation"
- **Quality Check**: "Check if X works correctly"

## Part of the Full Workflow

Deliver is phase 4 of 4 in the embrace (full) workflow:
1. Discover
2. Define
3. Develop
4. **Deliver** <- You are here

To run all 4 phases: `/octo:embrace`
