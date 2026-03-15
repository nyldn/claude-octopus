---
command: discover
description: "Discovery phase - Multi-AI research and exploration"
aliases:
  - probe
  - research-phase
---

# Discover - Discovery Phase 🔍

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:discover`, you MUST execute the structured workflow below.** You are PROHIBITED from doing the task directly, skipping the multi-provider research phase, or deciding the task is "too simple" for this workflow. The user chose this command deliberately — respect that choice.

---

When the user invokes this command (e.g., `/octo:discover <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "flow-discover", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:discover", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `flow-discover` skill. Skills use the `Skill` tool, not `Task`.

### Step 1: Ask Clarifying Questions

**CRITICAL: Before starting discovery, use the AskUserQuestion tool to gather context:**

Ask 3 clarifying questions to ensure focused research:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "How thorough should the research be?",
      header: "Research Intensity",
      multiSelect: false,
      options: [
        {label: "Quick (1-2 min)", description: "2 agents — fast problem space scan"},
        {label: "Standard (2-4 min)", description: "4-5 agents — balanced multi-perspective coverage (recommended)"},
        {label: "Deep (3-6 min)", description: "6-7 agents — exhaustive analysis with web search"}
      ]
    },
    {
      question: "What's your primary focus area?",
      header: "Focus",
      multiSelect: false,
      options: [
        {label: "Technical implementation (Recommended)", description: "Code patterns, APIs, architecture"},
        {label: "Best practices", description: "Industry standards and conventions"},
        {label: "Ecosystem & tools", description: "Libraries, frameworks, community"},
        {label: "Trade-offs & comparisons", description: "Pros/cons analysis"}
      ]
    },
    {
      question: "How should the output be formatted?",
      header: "Output",
      multiSelect: false,
      options: [
        {label: "Detailed report (Recommended)", description: "Comprehensive write-up"},
        {label: "Summary", description: "Concise key findings"},
        {label: "Comparison table", description: "Side-by-side format"},
        {label: "Recommendations", description: "Actionable next steps"}
      ]
    }
  ]
})
```

Map the intensity answer:
- "Quick" → `quick`
- "Standard" → `standard`
- "Deep" → `deep`

After receiving answers, incorporate them into the Skill invocation.

### Step 2: Invoke Skill with Intensity

```
Skill(skill: "flow-discover", args: "[intensity=quick|standard|deep] <user's arguments>")
```

Example: `Skill(skill: "flow-discover", args: "[intensity=standard] OAuth authentication patterns")`

### Step 3: Post-Completion — Interactive Next Steps

**CRITICAL: After the skill completes, you MUST ask the user what to do next. Do NOT end the session silently.**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Discovery phase complete. What would you like to do next?",
      header: "Next Steps",
      multiSelect: false,
      options: [
        {label: "Move to Define phase", description: "Scope and clarify requirements based on findings (/octo:define)"},
        {label: "Go deeper on a specific finding", description: "Research a particular area in more detail"},
        {label: "Run the full workflow", description: "Continue through all remaining phases (/octo:embrace)"},
        {label: "Export the research", description: "Save findings as a document"},
        {label: "Done for now", description: "I have what I need"}
      ]
    }
  ]
})
```

---

**Auto-loads the `flow-discover` skill for the research/discovery phase.**

## Quick Usage

Just use natural language:
```
"Research OAuth authentication patterns"
"Explore caching strategies for high-traffic APIs"
"Investigate microservices best practices"
```

## What Is Discover?

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

## Part of the Full Workflow

Discover is phase 1 of 4 in the embrace (full) workflow:
1. **Discover** <- You are here
2. Define
3. Develop
4. Deliver

To run all 4 phases: `/octo:embrace`
