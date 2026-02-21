---
command: discover
description: "Discovery phase - Multi-AI research and exploration"
aliases:
  - probe
  - research-phase
---

# Discover - Discovery Phase 🔍

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:discover <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:discover", args: "<user's arguments>")
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
      question: "How deep should the research go?",
      header: "Depth",
      multiSelect: false,
      options: [
        {label: "Quick overview (Recommended)", description: "1-2 min, surface-level scan"},
        {label: "Moderate depth", description: "2-3 min, standard coverage"},
        {label: "Comprehensive", description: "3-4 min, thorough analysis"},
        {label: "Deep dive", description: "4-5 min, exhaustive research"}
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

After receiving answers, incorporate them into the Skill invocation.

### Step 2: Invoke Skill

```
Skill(skill: "octo:discover", args: "<user's arguments>")
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
