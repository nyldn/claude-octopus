---
name: skill-prd
description: PRD creation - DO NOT LOAD THIS SKILL REPEATEDLY
---

# STOP - SKILL ALREADY LOADED

**DO NOT call Skill() again. DO NOT load any more skills. Execute directly.**

---

## PHASE 0: CLARIFICATION (MANDATORY)

Before writing ANY PRD content, ask:

```
I'll create a PRD for: [feature]

To make this targeted, please answer briefly:
1. **Target Users**: Who uses this? (devs, end-users, admins?)
2. **Core Problem**: What pain point? Any metrics?
3. **Success Criteria**: How to measure success?
4. **Constraints**: Technical, budget, timeline limits?
5. **Existing Context**: Greenfield or integrating?

(Type "skip" to proceed with assumptions)
```

**WAIT for response before Phase 1.**

---

## PHASE 1: QUICK RESEARCH (Max 60 seconds)

Only if unfamiliar. Max 2 web searches:
- One for domain/market context
- One for technical patterns (if needed)

---

## PHASE 2: WRITE PRD (~3,000 words target)

### CRITICAL: OPTIMIZATION RULES

**Scoring measures PRESENCE and QUALITY, not LENGTH.**

| Rule | Do This | Not This |
|------|---------|----------|
| Format | Bullets | Prose paragraphs |
| Diagrams | Simple numbered lists | ASCII art boxes |
| Examples | 1 comprehensive | 3 shallow |
| Personas | 2 detailed | 3+ redundant |
| FRs | 6 P0 only | 10 mixed priorities |
| Appendix | Brief + links | Full tutorials |
| Redundancy | Explain once, reference | Repeat in multiple sections |

### Structure (2,950 words total)

**1. Executive Summary (100 words)**
- Vision statement (1 sentence)
- Key value props (3-4 bullets)
- Target users (1 line)

**2. Problem Statement (150 words)**
- Quantified pain points (bullets with metrics)
- By user segment if applicable

**3. Goals & Metrics (150 words)**
- Table format: Goal | Metric | Target | Timeline
- P0/P1 priority tags

**4. Non-Goals (50 words)**
- Bullet list of explicit exclusions
- Brief "why" for each

**5. User Personas (400 words)**
- 2 personas only (cover the spectrum)
- Bullet format:
  ```
  **Name - Role**
  - Experience: X years, skills
  - Context: environment, tools
  - Pain point: specific frustration
  - Success: what they need
  ```

**6. Functional Requirements (1,200 words)**
- 6 P0 requirements only
- FR-001 format with acceptance criteria
- Defer P1/P2 to "Future Enhancements" section
- Given/When/Then format for acceptance criteria

**7. Implementation Phases (300 words)**
- 3-4 phases, bullet format
- Dependencies noted inline
- Time estimates per phase

**8. Risks & Mitigations (150 words)**
- Table: Risk | Impact | Mitigation
- Top 5 only

**9. AI Optimization Notes (200 words)**
- 1 comprehensive example (not 3)
- Error handling pattern
- Context requirements

**10. Technical Reference (100 words)**
- Essential configs/paths only
- Links to full documentation

**11. Self-Score (100 words)**
- Table format against 100-point framework

**12. Open Questions (50 words)**
- Bullet list with brief recommendations

---

## PHASE 3: SELF-SCORE

Score against 100-point framework:
- AI-Specific Optimization: 25 pts
- Traditional PRD Core: 25 pts
- Implementation Clarity: 30 pts
- Completeness: 20 pts

---

## PHASE 4: SAVE

Write to user-specified filename or generate one.

---

**START WITH PHASE 0 CLARIFICATION NOW.**
