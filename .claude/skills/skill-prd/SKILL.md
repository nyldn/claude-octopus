---
name: skill-prd
description: Write an AI-optimized PRD using multi-AI orchestration — use when scoping a new feature or product
context: fork
agent: Plan
---

# STOP - SKILL ALREADY LOADED

**DO NOT call Skill() again. DO NOT load any more skills. Execute directly.**

---

## PHASE 0: CLARIFICATION (MANDATORY)

Before writing ANY PRD content, you MUST ask the user these questions:

```
I need to understand your requirements before creating the PRD.

1. **Target Users**: Who will use this? (developers, end-users, admins, etc.)
2. **Core Problem**: What specific pain point does this solve? Any metrics?
3. **Success Criteria**: How will you measure if this succeeds?
4. **Constraints**: Any technical, budget, or timeline constraints?
5. **Existing Context**: Is this greenfield or integrating with existing systems?

Please answer these (even briefly) so I can create a more targeted PRD.
```

**WAIT for user response before proceeding to Phase 1.**

If user says "skip" or provides the feature description inline, extract what you can and note assumptions.

---

## PHASE 1: QUICK RESEARCH (Max 2 searches)

Only search if topic is unfamiliar. Limit to 2 web searches max:
- One for domain/market context
- One for technical patterns (if needed)

Do NOT over-research. 60 seconds max for this phase.

---

## PHASE 2: WRITE PRD

Structure:
1. **Executive Summary** - Vision + key value prop
2. **Problem Statement** - Quantified pain points by user segment
3. **Goals & Metrics** - SMART goals, P0/P1/P2 priority, success metrics table
4. **Non-Goals** - Explicit boundaries (what we WON'T do)
5. **User Personas** - 2-3 specific personas with use cases
6. **Functional Requirements** - FR-001 format with acceptance criteria
7. **Implementation Phases** - Dependency-ordered, time-boxed
8. **Risks & Mitigations** - Top 3-5 risks with mitigation strategies

---

## PHASE 2.5: ADVERSARIAL PRD REVIEW (RECOMMENDED)

**After drafting the PRD but BEFORE self-scoring, dispatch the draft to a second provider for adversarial review.** A single-model PRD has blind spots — cross-provider challenge surfaces wrong assumptions, uncovered scenarios, and contradictory requirements.

Dispatch the PRD draft to a different provider (Codex, Gemini, or Sonnet as fallback) with this prompt:

> "Challenge this PRD. What assumptions are wrong? What user scenarios are missing? What requirements contradict each other? What will the first user complaint be? What risk does this PRD ignore?"

**After receiving the challenge:**
- Revise the PRD to address valid challenges
- Note dismissed challenges in the Risks section if they have partial merit
- Add to PRD footer: `Adversarial review: applied`

**Skip with `--fast` or when user requests speed over thoroughness.** See `prd.md` command for full dispatch syntax.

---

## PHASE 3: SELF-SCORE

Score against 100-point framework:
- AI-Specific Optimization: 25 pts (sequential phases, non-goals, structured format)
- Traditional PRD Core: 25 pts (problem statement, goals, personas, specs)
- Implementation Clarity: 30 pts (FRs with codes, NFRs, architecture, phases)
- Completeness: 20 pts (risks, dependencies, examples, doc quality)

---

## PHASE 4: SAVE

Write to user-specified filename or generate based on feature name.

---

**START WITH PHASE 0 CLARIFICATION QUESTIONS NOW.**
