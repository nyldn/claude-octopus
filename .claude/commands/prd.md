---
name: prd
description: Write an AI-optimized PRD using multi-AI orchestration and 100-point scoring framework
arguments:
  - name: feature
    description: The feature or system to write a PRD for
    required: true
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

If topic is unfamiliar, do MAX 2 web searches:
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
