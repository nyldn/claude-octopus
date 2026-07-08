# Architecture: Models, Providers, and Execution Flow

This document explains how Claude Octopus orchestrates multiple AI providers and the execution flow of each workflow.

---

## Overview

Claude Octopus coordinates **nine AI providers** to give you multi-perspective analysis:

```
    +------------------+
    |   Claude Code    |  <-- Orchestrator (you talk to this)
    +--------+---------+
             |
    +--------v---------+
    | Claude Octopus   |  <-- Plugin coordinates providers
    +--------+---------+
             |
  +--+---+---+---+---+--+
  |  |   |   |   |   |  |
+-v--+ +-v-+ +v+ +v+ +v-+  +--v--+  +-v----+
|Cdx | |Gem| |Cl| |Pp| |OR|  |Ollma|  |Coplt |
|CLI | |CLI| |AI| |API |API|  |local|  |aspir.|
+----+ +---+ +--+ +--+ +--+  +-----+  +------+
  Core and optional providers are auto-detected at runtime.
```

---

## Provider → Model Mapping

| Provider | CLI Tool | Underlying Model | Cost Source |
|----------|----------|------------------|-------------|
| **Codex CLI** | `codex exec --model gpt-5.4` | GPT-5.4 | Your `OPENAI_API_KEY` |
| **Antigravity CLI** | `agy --print --sandbox` | Antigravity backend model (e.g. Gemini 3.1 Pro Preview via `OCTOPUS_AGY_MODEL`) | Included with your Antigravity access/subscription |
| **Claude** | Built-in | Claude Sonnet 4.6 / Opus 4.7 | Your Claude Code subscription |
| **Perplexity** | API-only | Sonar Pro / Sonar | Your `PERPLEXITY_API_KEY` |
| **OpenRouter** | API-only | 100+ models (GLM-5, Kimi K2.5, DeepSeek R1, etc.) | Your `OPENROUTER_API_KEY` |
| **Ollama** *(optional)* | `ollama run <model>` | Local models (llama3.3, mistral, etc.) | Free (local) |
| **Copilot** *(optional)* | `copilot -p` | GitHub models (Claude/GPT/Gemini) | GitHub Copilot subscription |
| **Qwen** *(optional)* | `qwen -p` | Qwen3-Coder | `QWEN_API_KEY` or Coding-Plan auth |
| **OpenCode** *(optional)* | `opencode run` | Multi-provider router | Your OpenCode auth |

> **Note:** Models are as of April 2026. The orchestrate.sh script uses the latest available models. Only Claude is required — all others are optional and auto-detected.

### Role → Model Mapping (v9.29+)

Role defaults refreshed based on April 2026 benchmark consensus. See [GPT-5.4 prompting guide](./GPT-5.4-PROMPTING.md) for dispatcher patterns.

| Role                 | Default Model         | Why                                                                 |
|----------------------|-----------------------|---------------------------------------------------------------------|
| `architect`          | Claude Opus 4.7       | SWE-bench Pro 64.3, MCP-Atlas +9.2, LMArena #1; UI/UX taste         |
| `strategist`         | Claude Opus 4.7       | Premium arbitration, architecture tradeoffs                         |
| `security-reviewer`  | Claude Opus 4.7       | Adversarial reasoning                                               |
| `code-reviewer`      | GPT-5.4               | Edge-case hunting; Terminal-Bench 75.1                              |
| `reviewer` (alias)   | → `code-reviewer`     | Back-compat for v9.28 callers                                       |
| `implementer`        | GPT-5.4               | Terminal-heavy execution, iterative patch/test loops                |
| `implementer-heavy`  | Claude Opus 4.7       | Opt-in only; greenfield / large refactors / UI-heavy builds         |
| `synthesizer`        | Claude Sonnet 4.6     | Best aggregator price/quality                                       |
| `researcher`         | Gemini 3.1 Pro Preview (via Antigravity `agy`)| Broad research + synthesis                                  |

**Opt-out:** `OCTOPUS_LEGACY_ROLES=1` restores the v9.28 mapping (GPT-5.4 everywhere for architect/reviewer/implementer, Opus 4.6 for strategist).

**Graceful fallback:** when the preferred CLI is unavailable (e.g. no Anthropic auth for architect), `lib/agents.sh` silently downshifts and logs a single notice instead of failing.

### What Each Provider Excels At

| Provider | Strengths | Best For |
|----------|-----------|----------|
| **Codex (OpenAI, GPT-5.4)** | Edge-case hunting, terminal execution, patch/test loops | Code review (`code-reviewer`), default implementation (`implementer`) |
| **Antigravity (`agy`, Google seat)** | Research synthesis, documentation, broad knowledge | Ecosystem research, best practices, alternative perspectives |
| **Claude (Opus 4.7)** | Planning, architecture, adversarial reasoning, UI/UX taste | `architect`, `strategist`, `security-reviewer`, `implementer-heavy` |
| **Claude (Sonnet 4.6)** | Aggregation, final synthesis, workhorse summarization | `synthesizer`; included with Claude Code subscription |
| **Perplexity** | Live web search, CVE lookups, current docs | Discover phase research, dependency analysis |
| **OpenRouter** | Access to 100+ models, cost routing | Alternative perspectives, budget-conscious workflows |
| **Ollama** *(optional)* | Zero-cost, offline, privacy | Brainstorming, fallback, air-gapped environments |
| **Qwen** *(optional)* | Qwen3-Coder via API-key or Coding-Plan auth, Chinese language support | Research and code review when Qwen credentials are configured |

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
| Codex |   | agy   |   <- Run in PARALLEL
| CLI   |   |(Antig)|
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
1. Codex CLI and Antigravity CLI (`agy`) run **in parallel** with the research prompt
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
          v
    +-----------+
    |   Codex   |   <- Step 1: Problem statement
    +-----------+
          |
          v
    +-----------+
    |    agy    |   <- Step 2: Success criteria
    +-----------+
          |
          v
    +-----------+
    |    agy    |   <- Step 3: Constraints
    +-----------+
          |
          v
    +-----------+
    |    agy    |   <- Step 4: Build consensus
    | Consensus |
    +-----------+
          |
          v
   Problem Definition
    + Requirements
```

**Execution:** (Sequential for coherent problem definition)
1. Codex defines the core problem statement (2-3 sentences)
2. Antigravity (`agy`) defines success criteria (3-5 measurable criteria)
3. Antigravity (`agy`) defines constraints and boundaries
4. Antigravity (`agy`) synthesizes all perspectives into unified requirements

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
| Codex |   | agy   |   <- PARALLEL: Implementation proposals
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
1. Available external providers such as Codex and Antigravity each propose implementation approaches
2. Claude merges the best elements from the provider responses
3. **Quality Gate** checks if merged approach meets 75% consensus threshold
4. If failed: Loop back for revision
5. If passed: Proceed to implementation

**Quality Gate:**
The quality gate is based on subtask success rate:
- Measures: percentage of subtasks that completed successfully
- Threshold: 75% (configurable via `CLAUDE_OCTOPUS_QUALITY_THRESHOLD`)
- If failed: Can retry, escalate to human review, or abort

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
| Codex |   | agy   |   <- PARALLEL: Different review angles
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
2. Antigravity (`agy`) reviews security, edge cases, compliance
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

| Workflow | Codex Cost | Antigravity Cost | Total |
|----------|------------|------------------|-------|
| discover | $0.01-0.02 | Included* | $0.01-0.02 + Codex |
| define | $0.01-0.02 | Included* | $0.01-0.02 + Codex |
| develop | $0.02-0.05 | Included* | $0.02-0.05 + Codex |
| deliver | $0.01-0.03 | Included* | $0.01-0.03 + Codex |
| debate | $0.02-0.05 | Included* | $0.02-0.05 + Codex |
| embrace | $0.05-0.10 | Included* | $0.05-0.10 + Codex |

**Note:** Claude costs are included in your Claude Code subscription (Pro, Max 5x, Max 20x). *Antigravity (`agy`) is included with the user's Antigravity access/subscription; backend cost depends on the selected `OCTOPUS_AGY_MODEL`.

### Cost Optimization

| Strategy | How |
|----------|-----|
| **Use one provider** | Only install Codex OR Antigravity (not both) |
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
#   Antigravity CLI: ready (agy authenticated)
```

### Graceful Degradation

| Available Providers | Behavior |
|--------------------|----------|
| Three or more external providers | Full multi-AI orchestration with broad external perspective coverage |
| Any one or two external providers | Multi-AI orchestration with available perspectives |
| Codex only | Dual perspective (Codex + Claude) |
| Antigravity only | Dual perspective (Antigravity + Claude) |
| Neither | Claude-only mode (basic functionality) |

---

## Visual Indicators

When multi-AI mode is active, you'll see these indicators:

| Indicator | Meaning |
|-----------|---------|
| 🐙 | Claude Octopus orchestration active |
| 🔴 | Codex CLI executing (OpenAI) |
| 🧭 | Antigravity CLI executing (Google seat) |
| 🔵 | Claude subagent processing |

**Example output:**
```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research mode
🔍 Discover Phase: Researching authentication patterns

🔴 Codex CLI: Analyzing implementation patterns...
🧭 Antigravity CLI: Researching ecosystem best practices...
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

- **[Command and Usage Reference](./COMMAND-REFERENCE.md)** - Commands, triggers, and provider indicators
- **[Documentation Guide](./README.md)** - Docs landing page
- **[Command Reference](./COMMAND-REFERENCE.md)** - All available commands
