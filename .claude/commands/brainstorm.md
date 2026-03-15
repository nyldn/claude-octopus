---
command: brainstorm
description: "Start a creative thought partner brainstorming session"
---

# /octo:brainstorm

## INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user invokes `/octo:brainstorm`, you MUST ask the mode selection question below BEFORE starting the session.** Do NOT default to Solo mode. Do NOT skip the question. The user must choose.

---

## Step 1: Ask Mode (MANDATORY)

You MUST use AskUserQuestion to ask this BEFORE doing anything else:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "How should we brainstorm?",
      header: "Mode",
      multiSelect: false,
      options: [
        {label: "Solo", description: "Claude-only thought partner session — fast and focused"},
        {label: "Team", description: "Multi-AI brainstorm — diverse perspectives from multiple providers"}
      ]
    }
  ]
})
```

**WAIT for the user's answer before proceeding.**

---

## Step 2: Run the Selected Mode

### If Solo Mode selected:

Standard thought partner session using four breakthrough techniques:
- Pattern Spotting, Paradox Hunting, Naming the Unnamed, Contrast Creation

**Session flow:**
1. Frame the exploration topic
2. Guided questioning (one question at a time — do NOT dump multiple questions)
3. Challenge generic claims until specific
4. Collaboratively name discovered concepts
5. Export session with breakthroughs summary

**See:** skill-thought-partner for full documentation.

### If Team Mode selected:

🐙 **CLAUDE OCTOPUS ACTIVATED** — Multi-AI Brainstorm

Providers:
🔴 Codex CLI — Technical feasibility and implementation angles
🟡 Gemini CLI — Lateral thinking and ecosystem connections
🔵 Claude — Synthesis, pattern naming, and moderation

**Team workflow:**
1. Frame the topic with the user (brief clarifying question if needed)
2. Dispatch parallel brainstorm queries to available providers using the Agent tool:
   - Launch 2-3 agents (one per available provider) with `run_in_background: true`
   - Each agent gets a tailored brainstorm prompt emphasizing its perspective
   - Codex: "Think about technical implementation, feasibility, architecture tradeoffs"
   - Gemini: "Think about ecosystem, adjacent innovations, unconventional approaches"
   - Claude: "Think about patterns, paradoxes, and naming opportunities"
3. Collect diverse perspectives from all agents
4. Synthesize across perspectives — find convergence and surprising divergence
5. Present the synthesis to the user
6. Challenge and build on combined ideas interactively
7. Export session with multi-perspective breakthroughs

**Why Team mode works:** Different AI models have different training biases, knowledge distributions, and reasoning patterns. Combined perspectives surface ideas that no single model would generate alone.

---

## Validation Gates

- Mode question was asked via AskUserQuestion (not assumed)
- User's choice was respected
- If Team mode: at least 2 providers were queried
- Session ends with a breakthroughs summary

### Prohibited Actions

- Defaulting to Solo mode without asking
- Skipping the mode selection question
- In Team mode: only using Claude (must dispatch to external providers)
