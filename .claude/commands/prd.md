---
name: prd
description: Write an AI-optimized PRD using multi-AI orchestration and 100-point scoring framework
arguments:
  - name: feature
    description: The feature or system to write a PRD for
    required: true
---

## STOP - DO NOT INVOKE /skill OR Skill() AGAIN

Feature to document: **$ARGUMENTS.feature**

---

## PHASE 0: CLARIFICATION (MANDATORY)

Ask the user:

```
I'll create a PRD for: **$ARGUMENTS.feature**

To make this targeted, please answer briefly:
1. **Target Users**: Who uses this?
2. **Core Problem**: What pain point? Metrics?
3. **Success Criteria**: How to measure?
4. **Constraints**: Technical, budget, timeline?
5. **Existing Context**: Greenfield or integration?

(Type "skip" to proceed with assumptions)
```

**WAIT for response.**

---

## PHASE 1: QUICK RESEARCH (Max 60 sec)

Max 2 web searches if topic unfamiliar.

---

## PHASE 2: WRITE PRD (~3,000 words)

### OPTIMIZATION RULES (CRITICAL)

**Scoring = PRESENCE + QUALITY, not LENGTH.**

- **Bullets > prose** (saves 500 words)
- **Simple lists > ASCII diagrams** (saves 200 words)
- **1 example > 3 examples** (saves 400 words)
- **2 personas > 3 personas** (saves 200 words)
- **6 P0 FRs > 10 mixed FRs** (saves 800 words)
- **Brief appendix + links > full tutorials** (saves 300 words)
- **No redundancy** - explain once, reference elsewhere

### Structure

1. Executive Summary (100 words) - bullets
2. Problem Statement (150 words) - quantified bullets
3. Goals & Metrics (150 words) - table format
4. Non-Goals (50 words) - bullet list
5. 2 User Personas (400 words) - bullet format
6. 6 P0 Functional Requirements (1,200 words) - FR-001 with acceptance criteria
7. 3-4 Implementation Phases (300 words) - bullets with dependencies
8. Top 5 Risks (150 words) - table
9. AI Optimization Notes (200 words) - 1 example
10. Technical Reference (100 words) - links + essentials
11. Self-Score (100 words) - table
12. Open Questions (50 words) - bullets

---

## PHASE 3: SELF-SCORE

100-point framework (table format).

---

## PHASE 4: SAVE

Write to user-specified filename or generate one.

---

**BEGIN PHASE 0 FOR: $ARGUMENTS.feature**
