---
command: research
description: Deep research with multi-source synthesis and comprehensive analysis
---

# Research - Deep Multi-AI Research

**Your first output line MUST be:** `🐙 Octopus Research`

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:research`, you MUST execute the structured research workflow below.** You are PROHIBITED from answering directly, skipping the multi-provider research, or deciding the topic is "too simple" for deep research. The user chose this command deliberately — respect that choice.

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST execute this command by invoking the corresponding skill via the Skill tool. You are PROHIBITED from:**
- ❌ Using the Agent tool to research/implement yourself instead of invoking the skill
- ❌ Using WebFetch/Read/Grep as a substitute for multi-provider dispatch
- ❌ Skipping `orchestrate.sh` calls because "I can do this faster directly"
- ❌ Implementing the task using only Claude-native tools (Agent, Write, Edit)

**Multi-LLM orchestration is the purpose of this command.** If you execute using only Claude, you've violated the command's contract.

---

When the user invokes this command (e.g., `/octo:research <arguments>`):

### Step 1: Resolve Research Breadth/Intensity

First parse explicit flags from the user's arguments:
- `--breadth=light|standard|exhaustive`
- `--intensity=quick|standard|deep`

Map breadth to intensity when intensity is absent:
- `light` -> `quick`
- `standard` -> `standard`
- `exhaustive` -> `deep`

If neither flag is present, use the AskUserQuestion tool to select intensity:

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

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octopus-research", args: "[breadth=light|standard|exhaustive] [intensity=quick|standard|deep] <user's arguments without routing flags>")
```

Examples:
- `Skill(skill: "octopus-research", args: "[breadth=standard] [intensity=standard] OAuth 2.0 authentication patterns")`
- `/octo:research --breadth=exhaustive current agent orchestration patterns` -> `Skill(skill: "octopus-research", args: "[breadth=exhaustive] [intensity=deep] current agent orchestration patterns")`

**✗ INCORRECT - Do NOT use these:**
```
Using the octo:discover skill       ❌ Wrong here! Research has a dedicated skill contract
Skill(skill: "flow-discover", ...)   ❌ Wrong! Internal skill name, not resolvable by Skill tool
Skill(skill: "discover", ...)        ❌ Wrong! Must use full namespaced name
Task(subagent_type: "octo:discover", ...)  ❌ Wrong! This is a skill, not an agent type
```

---

**Auto-loads the dedicated research skill for comprehensive multi-provider research tasks.**

## Quick Usage

Just use natural language:
```
"Research OAuth 2.0 authentication patterns"
"Deep research on microservices architecture best practices"
"Research the trade-offs between Redis and Memcached"
```

## What Is Research?

A dedicated research workflow aligned with the **Discover** phase of the Double Diamond methodology:
- Multi-AI research (Claude + Gemini + Codex)
- Comprehensive analysis of options
- Trade-off evaluation
- Best practice identification

## Report Format (MANDATORY)

All research output MUST follow this structured template:

### 1. Executive Summary
2-3 sentences summarizing the key finding. What does the reader need to know?

### 2. Key Themes
Group findings into 3-5 themes. Each theme gets a heading, a summary paragraph, and supporting evidence.

### 3. Key Takeaways
Numbered list of actionable insights. Each takeaway should be specific enough to act on.

### 4. Sources & Attribution
Every factual claim MUST cite its source. Claims without sources should be explicitly marked as **inference** or **opinion**. Format:
- `[Source: <name/URL>]` for verified facts
- `[Inference]` for conclusions drawn from evidence
- `[Opinion: <provider>]` for provider-specific perspectives

### 5. Methodology
Brief note on what was researched, which providers contributed, and any gaps or limitations:
- Providers used and their roles
- Search queries or exploration paths taken
- Areas not covered or needing deeper investigation
- Cross-references checked and gaps acknowledged

### Quality Rules
- **No unsourced claims** — every assertion needs either a source or an explicit [Inference] tag
- **Acknowledge gaps** — if a topic wasn't fully explored, say so
- **Cross-reference** — when providers disagree, note the disagreement and which evidence is stronger

## Natural Language Examples

```
"Research GraphQL vs REST API design patterns"
"I need deep research on Kubernetes security best practices"
"Research authentication strategies for microservices"
```
