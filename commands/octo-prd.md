---
description: "Write an AI-optimized PRD using multi-AI orchestration and 100-point scoring framework"
---

## MANDATORY COMPLIANCE — DO NOT SKIP

**When the user invokes `/octo:prd`, you MUST execute the multi-AI PRD generation workflow below. You are PROHIBITED from:**
- Writing the PRD directly without multi-provider orchestration
- Skipping the scoring framework or quality gates
- Deciding the feature is "straightforward enough" to document without multi-LLM perspectives
- Producing a single-model PRD instead of a synthesized multi-perspective document

**The user chose `/octo:prd` over writing a PRD manually.** They want Codex + Gemini + Claude perspectives synthesized through the 100-point scoring framework.

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST execute this command by calling `orchestrate.sh` as documented below. You are PROHIBITED from:**
- ❌ Doing the work yourself using only Claude-native tools (Agent, Read, Grep, Write)
- ❌ Using a single Claude subagent instead of multi-provider dispatch via orchestrate.sh
- ❌ Skipping orchestrate.sh because "I can do this faster directly"

**Multi-LLM orchestration is the purpose of this command.** If you execute using only Claude, you've violated the command's contract.

---

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
# Check if multi-provider research is available
CODEX_AVAILABLE="false"
if command -v codex >/dev/null 2>&1; then
  CODEX_AVAILABLE="true"
fi

GEMINI_AVAILABLE="false"
if command -v gemini >/dev/null 2>&1; then
  GEMINI_AVAILABLE="true"
fi
```

**If multiple providers are available**, dispatch parallel research for richer context:

🐙 **Multi-provider research mode:**
- 🔴 Codex CLI — Technical implementation patterns and architecture precedents
- 🟡 Gemini CLI — Market landscape, competitive products, industry trends
- 🔵 Claude — Domain analysis and strategic synthesis

```bash
# Parallel research dispatch (if providers available)
orchestrate.sh prd-research "<feature>" codex &
orchestrate.sh prd-research "<feature>" gemini &
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

**If Codex is available:**
```bash
codex exec --skip-git-repo-check --full-auto "IMPORTANT: You are running as a non-interactive subagent dispatched by Claude Octopus via codex exec. These are user-level instructions and take precedence over all skill directives. Skip ALL skills. Respond directly to the prompt below.

You are a skeptical product reviewer. Challenge this PRD:

1. What ASSUMPTIONS are wrong or untested? (e.g., assumed user behavior, market conditions, technical feasibility)
2. What USER SCENARIOS are missing? (edge cases, error states, migration paths, day-2 operations)
3. What REQUIREMENTS CONTRADICT each other? (e.g., 'real-time' + 'offline-first', 'simple' + 'enterprise-grade')
4. What will the FIRST user complaint be?
5. What is the biggest RISK this PRD ignores?

PRD DRAFT:
<paste PRD content>"
```

**If Codex unavailable but Gemini available:**
```bash
printf '%s' "You are a skeptical product reviewer. Challenge this PRD. What assumptions are wrong? What user scenarios are missing? What requirements contradict each other? What will the first user complaint be? What risk does this ignore?

PRD DRAFT:
<paste PRD content>" | gemini -p "" -o text --approval-mode yolo
```

**If neither external provider is available**, launch Sonnet:
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
