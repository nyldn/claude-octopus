# Architecture: Models, Providers, and Execution Flow

This document explains how Claude Octopus orchestrates multiple AI providers and the execution flow of each workflow.

---

## Overview

Claude Octopus coordinates **three AI providers** to give you multi-perspective analysis:

```
    +------------------+
    |   Claude Code    |  <-- Orchestrator (you talk to this)
    +--------+---------+
             |
    +--------v---------+
    | Claude Octopus   |  <-- Plugin coordinates providers
    +--------+---------+
             |
     +-------+-------+
     |       |       |
+----v--+ +--v---+ +-v----+
| Codex | |Gemini| |Claude|
|  CLI  | | CLI  | |  AI  |
+-------+ +------+ +------+
    |         |        |
+---v---+ +---v---+ +--v---+
|OpenAI | |Google | |Anthr.|
| API   | |  API  | | API  |
+-------+ +-------+ +------+
```

---

## Provider → Model Mapping

| Provider | CLI Tool | Underlying Model | Cost Source |
|----------|----------|------------------|-------------|
| **Codex CLI** | `codex exec` | GPT-4 / GPT-4 Turbo | Your `OPENAI_API_KEY` |
| **Gemini CLI** | `gemini -y` | Gemini Pro / Gemini 1.5 Pro | Your `GEMINI_API_KEY` |
| **Claude** | Built-in | Claude 3.5 Sonnet / Opus | Your Claude Code subscription |

### What Each Provider Excels At

| Provider | Strengths | Best For |
|----------|-----------|----------|
| **Codex (OpenAI)** | Code generation, structured output, technical analysis | Implementation approaches, code patterns, API design |
| **Gemini (Google)** | Research synthesis, documentation, broad knowledge | Ecosystem research, best practices, alternative perspectives |
| **Claude** | Strategic synthesis, nuanced analysis, code review | Final synthesis, quality assessment, moderation |

---

## Execution Flow by Workflow

### Discover Phase (probe)

**Trigger:** `octo research X` or `/octo:discover`

```
User Request
     |
     v
+--------------------+
|   Claude Octopus   |
|    Orchestrator    |
+---------+----------+
          |
    +-----+-----+
    |           |
    v           v
+-------+   +-------+
| Codex |   |Gemini |   <- Run in PARALLEL
| CLI   |   | CLI   |
+---+---+   +---+---+
    |           |
    v           v
"Technical   "Ecosystem
 analysis"    research"
    |           |
    +-----+-----+
          |
          v
    +----------+
    |  Claude  |   <- SEQUENTIAL (after both complete)
    | Synthesis|
    +----------+
          |
          v
    Final Research
       Report
```

**Execution:**
1. Codex CLI and Gemini CLI run **in parallel** with the research prompt
2. Both responses are collected
3. Claude synthesizes both perspectives into a unified report

**Typical duration:** 30-60 seconds  
**Typical cost:** $0.01-0.05 (depending on prompt length)

---

### Define Phase (grasp)

**Trigger:** `octo define X` or `/octo:define`

```
User Request
     |
     v
+--------------------+
|   Claude Octopus   |
+---------+----------+
          |
    +-----+-----+
    |           |
    v           v
+-------+   +-------+
| Codex |   |Gemini |   <- PARALLEL
+---+---+   +---+---+
    |           |
    v           v
"Technical   "Business
 constraints"  requirements"
    |           |
    +-----+-----+
          |
          v
    +----------+
    |  Claude  |
    | Consensus|
    +----------+
          |
          v
   Problem Definition
    + Requirements
```

**Execution:**
1. Codex focuses on technical constraints and system requirements
2. Gemini focuses on business context and user needs
3. Claude builds consensus and creates unified requirements

---

### Develop Phase (tangle)

**Trigger:** `octo build X` or `/octo:develop`

```
User Request
     |
     v
+--------------------+
|   Claude Octopus   |
+---------+----------+
          |
    +-----+-----+
    |           |
    v           v
+-------+   +-------+
| Codex |   |Gemini |   <- PARALLEL: Implementation proposals
+---+---+   +---+---+
    |           |
    v           v
"Approach A" "Approach B"
    |           |
    +-----+-----+
          |
          v
    +----------+
    |  Claude  |
    |  Merge   |
    +----------+
          |
          v
    +----------+
    | Quality  |   <- 75% CONSENSUS GATE
    |   Gate   |
    +----------+
       |     |
   PASS?    FAIL?
       |     |
       v     v
   Continue  Revise
```

**Execution:**
1. Codex and Gemini each propose implementation approaches
2. Claude merges the best elements from both
3. **Quality Gate** checks if merged approach meets 75% consensus threshold
4. If failed: Loop back for revision
5. If passed: Proceed to implementation

**Quality Gate Dimensions:**
- Code Quality (25%)
- Security (35%)
- Best Practices (20%)
- Completeness (20%)

---

### Deliver Phase (ink)

**Trigger:** `octo review X` or `/octo:deliver`

```
User Request
     |
     v
+--------------------+
|   Claude Octopus   |
+---------+----------+
          |
    +-----+-----+
    |           |
    v           v
+-------+   +-------+
| Codex |   |Gemini |   <- PARALLEL: Different review angles
+---+---+   +---+---+
    |           |
    v           v
"Code quality""Security &
 review"       edge cases"
    |           |
    +-----+-----+
          |
          v
    +----------+
    |  Claude  |
    | Validate |
    +----------+
          |
          v
    +----------+
    | Quality  |
    |  Score   |
    +----------+
          |
          v
   Validation Report
   + Go/No-Go Decision
```

**Execution:**
1. Codex reviews code quality, patterns, maintainability
2. Gemini reviews security, edge cases, compliance
3. Claude synthesizes into validation report
4. Quality score determines go/no-go recommendation

**Validation Thresholds:**
| Score | Status | Recommendation |
|-------|--------|----------------|
| >= 90% | PASSED | Ship it |
| 75-89% | WARNING | Ship with caution |
| < 75% | FAILED | Do not ship |

---

### Debate (grapple)

**Trigger:** `octo debate X vs Y` or `/octo:debate`

```
User Question
     |
     v
+--------------------+
|   Claude Octopus   |
+---------+----------+
          |
     Round 1
    +-----+-----+
    |     |     |
    v     v     v
+-----+ +-----+ +-----+
|Codex| |Gemin| |Claud|  <- All 3 PARALLEL
+--+--+ +--+--+ +--+--+
   |       |       |
   v       v       v
"Pro X"  "Pro Y" "Moderator
                  analysis"
   |       |       |
   +---+---+---+---+
       |       |
     Round 2 (optional)
       |
       v
   +-------+
   |Claude |
   |Synth. |
   +-------+
       |
       v
  Final Verdict
  + Recommendation
```

**Execution:**
1. **Round 1:** All three providers argue their positions in parallel
2. **Round 2+ (optional):** Rebuttals and counter-arguments
3. **Synthesis:** Claude moderates and produces final verdict

**Debate Styles:**
| Style | Rounds | Approach |
|-------|--------|----------|
| quick | 1 | Fast positions, immediate synthesis |
| thorough | 2-3 | Multiple rounds of debate |
| adversarial | 3 | Providers actively critique each other |
| collaborative | 2 | Providers build on each other's ideas |

---

### Full Workflow (embrace)

**Trigger:** `/octo:embrace`

```
User Request
     |
     v
+---------+
| DISCOVER|  <- Phase 1
+---------+
     |
     v
+---------+
|  DEFINE |  <- Phase 2
+---------+
     |
     v
+---------+
| DEVELOP |  <- Phase 3 (with quality gate)
+---------+
     |
     v
+---------+
| DELIVER |  <- Phase 4
+---------+
     |
     v
  Complete
  Feature
```

**Execution:**
All four phases run sequentially. Each phase uses the output of the previous phase as context.

**Typical duration:** 2-5 minutes  
**Typical cost:** $0.10-0.30

---

## Cost Breakdown

### Per-Query Estimates

| Workflow | Codex Cost | Gemini Cost | Total |
|----------|------------|-------------|-------|
| discover | $0.01-0.02 | $0.01-0.02 | $0.02-0.04 |
| define | $0.01-0.02 | $0.01-0.02 | $0.02-0.04 |
| develop | $0.02-0.05 | $0.02-0.05 | $0.04-0.10 |
| deliver | $0.01-0.03 | $0.01-0.03 | $0.02-0.06 |
| debate | $0.02-0.05 | $0.02-0.05 | $0.05-0.15 |
| embrace | $0.05-0.10 | $0.05-0.10 | $0.10-0.30 |

**Note:** Claude costs are included in your Claude Code subscription (Pro, Max 5x, Max 20x).

### Cost Optimization

| Strategy | How |
|----------|-----|
| **Use one provider** | Only install Codex OR Gemini (not both) |
| **Skip unnecessary phases** | Use `/octo:develop` instead of `/octo:embrace` for simple tasks |
| **Use Claude-only** | For simple tasks, don't use "octo" prefix - just ask directly |

---

## Provider Detection

Claude Octopus auto-detects which providers are available:

```bash
# Check status
/octo:setup

# Output example:
# Providers:
#   Codex CLI: ready (OPENAI_API_KEY found)
#   Gemini CLI: ready (OAuth authenticated)
```

### Graceful Degradation

| Available Providers | Behavior |
|--------------------|----------|
| Codex + Gemini | Full multi-AI orchestration |
| Codex only | Dual perspective (Codex + Claude) |
| Gemini only | Dual perspective (Gemini + Claude) |
| Neither | Claude-only mode (basic functionality) |

---

## Visual Indicators

When multi-AI mode is active, you'll see these indicators:

| Indicator | Meaning |
|-----------|---------|
| 🐙 | Claude Octopus orchestration active |
| 🔴 | Codex CLI executing (OpenAI) |
| 🟡 | Gemini CLI executing (Google) |
| 🔵 | Claude subagent processing |

**Example output:**
```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research mode
🔍 Discover Phase: Researching authentication patterns

🔴 Codex CLI: Analyzing implementation patterns...
🟡 Gemini CLI: Researching ecosystem best practices...
🔵 Claude: Synthesizing perspectives...

[Final synthesis report]
```

---

## Under the Hood: orchestrate.sh

All workflows are powered by `scripts/orchestrate.sh`:

```bash
# Direct CLI usage (advanced)
./scripts/orchestrate.sh probe "research OAuth patterns"
./scripts/orchestrate.sh tangle "implement authentication"
./scripts/orchestrate.sh ink "review auth code"
./scripts/orchestrate.sh embrace "complete auth feature"
```

The plugin wraps these commands and provides:
- Natural language triggers
- Session management
- Result storage
- Quality gates

---

## See Also

- **[Visual Indicators Guide](./VISUAL-INDICATORS.md)** - Visual feedback system
- **[Triggers Guide](./TRIGGERS.md)** - What activates each workflow
- **[CLI Reference](./CLI-REFERENCE.md)** - Direct CLI usage
- **[Command Reference](./COMMAND-REFERENCE.md)** - All available commands
