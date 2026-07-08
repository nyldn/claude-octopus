---
command: prd
description: Write an AI-optimized PRD using multi-AI orchestration and 100-point scoring framework
arguments:
  - name: feature
    description: The feature or system to write a PRD for
    required: true
---

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:prd`, you MUST follow the orchestrated PRD workflow below.** You are PROHIBITED from writing the PRD directly without the required clarification, research, scoring, and `orchestrate.sh` steps.

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST execute this command by calling `orchestrate.sh` as documented below. You are PROHIBITED from:**
- ❌ Doing the work yourself using only Claude-native tools (Agent, Read, Grep, Write)
- ❌ Using a single Claude subagent instead of multi-provider dispatch via orchestrate.sh
- ❌ Skipping orchestrate.sh because "I can do this faster directly"

**Multi-LLM orchestration is the purpose of this command.** If you execute using only Claude, you've violated the command's contract.

## STOP - DO NOT INVOKE /skill OR Skill() AGAIN

This command is already executing. The feature to document is: **$ARGUMENTS.feature**

---

## PHASE 0: CLARIFICATION (MANDATORY - DO THIS FIRST)

Before writing ANY PRD content, ask the user:

```
I'll create a PRD for: **$ARGUMENTS.feature**

To make this PRD highly targeted, please answer briefly:

1. **Target Users**: Who will use this? (developers, end-users, admins, agencies?)
2. **Core Problem**: What pain point does this solve? Any metrics on current impact?
3. **Success Criteria**: How will you measure success? (KPIs, adoption rate, time saved?)
4. **Constraints**: Any technical, budget, timeline, or platform constraints?
5. **Existing Context**: Greenfield project or integrating with existing systems?

(Type "skip" to proceed with assumptions, or answer inline)
```

**WAIT for user response before proceeding.**

---

## PHASE 1: QUICK RESEARCH (Max 60 seconds)

**Check provider availability first:**

```bash
set -euo pipefail

# Check if multi-provider research is available
CODEX_AVAILABLE="false"
if command -v codex >/dev/null 2>&1; then
  CODEX_AVAILABLE="true"
fi

AGY_AVAILABLE="false"
if command -v agy >/dev/null 2>&1; then
  AGY_AVAILABLE="true"
fi
```

**If multiple providers are available**, dispatch parallel research for richer context:

🐙 **Multi-provider research mode:**
- 🔴 Codex CLI — Technical implementation patterns and architecture precedents
- 🧭 Antigravity CLI — Market landscape, competitive products, industry trends (Google seat)
- 🔵 Claude — Domain analysis and strategic synthesis

```bash
# Parallel research dispatch (if providers available)
if [[ "$CODEX_AVAILABLE" == "true" ]]; then
  orchestrate.sh prd-research "<feature>" codex &
fi
if [[ "$AGY_AVAILABLE" == "true" ]]; then
  orchestrate.sh prd-research "<feature>" agy &
fi
wait
```

**If single-provider only**, do MAX 2 web searches:
- One for domain/market context
- One for technical patterns (only if needed)

Do NOT over-research. Move to writing quickly.

---

## PHASE 2: WRITE PRD

Include these sections:
1. Executive Summary (vision + key value)
2. Problem Statement (quantified, by user segment)
3. Goals & Metrics (SMART, P0/P1/P2, success metrics table)
4. Non-Goals (explicit boundaries)
5. User Personas (2-3 specific personas)
6. Functional Requirements (FR-001 format)
7. Implementation Phases (dependency-ordered)
8. Risks & Mitigations

---

## PHASE 2.5: ADVERSARIAL PRD REVIEW (RECOMMENDED)

**After drafting the PRD but BEFORE self-scoring, dispatch the draft to a second provider for adversarial review.** A single-model PRD has blind spots — cross-provider challenge surfaces wrong assumptions, uncovered scenarios, and contradictory requirements.

**If an external provider is available, dispatch through Octopus routing:**
```bash
review_provider=""
command -v codex >/dev/null 2>&1 && review_provider="codex"
[[ -z "$review_provider" ]] && command -v agy >/dev/null 2>&1 && review_provider="agy"

if [[ -n "$review_provider" ]]; then
  "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" spawn "$review_provider" \
    "You are a skeptical product reviewer. Challenge this PRD:

1. What ASSUMPTIONS are wrong or untested? (e.g., assumed user behavior, market conditions, technical feasibility)
2. What USER SCENARIOS are missing? (edge cases, error states, migration paths, day-2 operations)
3. What REQUIREMENTS CONTRADICT each other? (e.g., 'real-time' + 'offline-first', 'simple' + 'enterprise-grade')
4. What will the FIRST user complaint be?
5. What is the biggest RISK this PRD ignores?

PRD DRAFT:
<paste PRD content>"
fi
```

**If no external provider is available**, launch Sonnet:
```
Agent(
  model: "sonnet",
  description: "Adversarial PRD review",
  prompt: "Challenge this PRD. What assumptions are wrong? What scenarios are missing? What requirements contradict? What will the first user complaint be?

PRD DRAFT:
<PRD content>"
)
```

**After receiving the challenge:**
- Revise the PRD to address valid challenges (add missing scenarios, resolve contradictions, note assumptions)
- Dismiss irrelevant challenges but note them in the Risks section if they have partial merit
- Add to the PRD footer: `Adversarial review: applied (provider: <provider>)`

**Skip with `--fast` or when user explicitly requests speed over thoroughness.**

---

## PHASE 3: SELF-SCORE (100-point framework)

- AI-Specific Optimization: 25 pts
- Traditional PRD Core: 25 pts
- Implementation Clarity: 30 pts
- Completeness: 20 pts

---

## PHASE 4: SAVE

Write to user-specified filename or generate one.

---

**BEGIN PHASE 0 - ASK CLARIFICATION QUESTIONS FOR: $ARGUMENTS.feature**
