---
command: brainstorm
description: "Start a creative thought partner brainstorming session"
---

# /octo:brainstorm

Start a structured brainstorming session using four breakthrough techniques.

**Usage:**
```
/octo:brainstorm
/octo:brainstorm [topic]
```

**What it does:**
- Acts as a creative thought partner
- Uses Pattern Spotting, Paradox Hunting, Naming the Unnamed, Contrast Creation
- Helps discover hidden insights and unique strategies
- Documents breakthroughs and named concepts

**See:** skill-thought-partner for full documentation.

---

## Mode Selection

Before starting, determine the brainstorming intensity:

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

### Solo Mode (default)

Standard thought partner session:
1. Frame the exploration topic
2. Guided questioning (one at a time)
3. Challenge generic claims until specific
4. Collaboratively name discovered concepts
5. Export session with breakthroughs summary

### Team Mode (multi-LLM)

🐙 **CLAUDE OCTOPUS ACTIVATED** — Multi-AI Brainstorm

Providers:
🔴 Codex CLI — Technical feasibility and implementation angles
🟡 Gemini CLI — Lateral thinking and ecosystem connections
🔵 Claude — Synthesis, pattern naming, and moderation

**Team workflow:**
1. Frame the topic with the user
2. Dispatch parallel brainstorm queries to available providers:
   ```bash
   # Each provider gets a tailored brainstorm prompt
   orchestrate.sh brainstorm-probe "<topic>" "<provider>"
   ```
3. Collect diverse perspectives (each provider applies different techniques)
4. Synthesize across perspectives — find convergence and surprising divergence
5. Challenge and build on combined ideas with the user
6. Export session with multi-perspective breakthroughs

**Why Team mode works:** Different AI models have different training biases, knowledge distributions, and reasoning patterns. Combined perspectives surface ideas that no single model would generate alone.

---

**Example:**
```
/octo:brainstorm my approach to customer onboarding

→ Solo or Team mode?
→ [Solo] Starting thought partner session...
→ "What topic or idea would you like to explore today?"

→ [Team] 🐙 Multi-AI brainstorm activated...
→ 🔴 Codex: Technical onboarding patterns...
→ 🟡 Gemini: Industry best practices and emerging trends...
→ 🔵 Claude: Synthesizing perspectives and naming patterns...
```
