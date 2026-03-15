---
command: research
description: Deep research with multi-source synthesis and comprehensive analysis
---

# Research - Deep Multi-AI Research

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:research`, you MUST execute the structured research workflow below.** You are PROHIBITED from answering directly, skipping the multi-provider research, or deciding the topic is "too simple" for deep research. The user chose this command deliberately — respect that choice.

---

When the user invokes this command (e.g., `/octo:research <arguments>`):

### Step 1: Ask Research Intensity

**CRITICAL: Before starting research, use the AskUserQuestion tool to select intensity:**

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
    }
  ]
})
```

Map the answer to an intensity value:
- "Quick" → `quick`
- "Standard" → `standard`
- "Deep" → `deep`

### Step 2: Invoke Skill with Intensity

**✓ CORRECT - Use the Skill tool with the skill's registered name:**
```
Skill(skill: "flow-discover", args: "[intensity=quick|standard|deep] <user's arguments>")
```

Example: `Skill(skill: "flow-discover", args: "[intensity=standard] OAuth 2.0 authentication patterns")`

**✗ INCORRECT - Do NOT use these names:**
```
Skill(skill: "octo:discover", ...)   ❌ Wrong! "octo:discover" is the command name, not the skill name
Skill(skill: "discover", ...)        ❌ Wrong! Use the full skill name "flow-discover"
Task(subagent_type: "octo:discover", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** The command is `/octo:discover` but the skill file is named `flow-discover`. Always use the skill's registered name with the Skill tool.

---

**Auto-loads the `flow-discover` skill for comprehensive research tasks.**

## Quick Usage

Just use natural language:
```
"Research OAuth 2.0 authentication patterns"
"Deep research on microservices architecture best practices"
"Research the trade-offs between Redis and Memcached"
```

## What Is Research?

An alias for the **Discover** phase of the Double Diamond methodology:
- Multi-AI research (Claude + Gemini + Codex)
- Comprehensive analysis of options
- Trade-off evaluation
- Best practice identification

## Natural Language Examples

```
"Research GraphQL vs REST API design patterns"
"I need deep research on Kubernetes security best practices"
"Research authentication strategies for microservices"
```
