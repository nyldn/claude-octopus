---
name: skill-prd-score
description: |
  Score an existing PRD against the 100-point AI-optimization framework.
  Identifies gaps and provides actionable improvement suggestions.
  Use /octo:prd-score <file> to invoke.
---

# PRD Scoring Skill

> **EXECUTION NOTE**: This skill is now loaded. DO NOT search for this file or try to locate it.
> Proceed directly to Step 1 below. The user's PRD file path is in the conversation context.

## Purpose

Evaluate existing PRDs against the 100-point AI-optimization framework. Provides section-by-section scoring with specific improvement suggestions.

## When This Skill Activates

**Via command only** (to prevent recursive activation):
- `/octo:prd-score docs/my-prd.md`
- `/octo:prd-score requirements/checkout-spec.md`

Note: Natural language triggers removed due to recursive activation issues.

## Visual Indicator

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - PRD Scoring Mode
📊 Evaluating PRD: [File Name]

Scoring against 100-point AI-optimization framework...
```

---

## Scoring Workflow

### Step 1: Load the PRD

Read the PRD file specified by the user. If no file specified, ask:

```
Which PRD would you like me to score? Please provide:
- A file path (relative or absolute)
- Or paste the PRD content directly
```

### Step 2: Section-by-Section Evaluation

Score each category using the detailed rubric below:

---

## 100-Point Scoring Framework

### Category A: AI-Specific Optimization (25 points)

| Criterion | Points | What to Check |
|-----------|--------|---------------|
| **Sequential Phases** | 0-10 | Are implementation phases ordered by dependencies? Can AI execute Phase N without completing Phase N-1? Each phase should be 5-15 minutes of work. |
| **Explicit Non-Goals** | 0-8 | Does the PRD have a dedicated Non-Goals section? AI cannot infer omission - what's explicitly OUT of scope? |
| **Structured Format** | 0-7 | Is the format parseable? Uses FR codes, consistent headings, Given-When-Then acceptance criteria? |

**Scoring Guide:**
- 10/10 Sequential: Phases numbered, dependencies explicit, each phase standalone executable
- 8/8 Non-Goals: 3+ explicit boundaries, prevents scope creep
- 7/7 Structure: FR-XXX codes, priority tags, consistent markdown

---

### Category B: Traditional PRD Core (25 points)

| Criterion | Points | What to Check |
|-----------|--------|---------------|
| **Problem Statement** | 0-7 | Quantified pain points? Metrics showing impact? "Users waste X hours" not "users are frustrated" |
| **Goals & Metrics** | 0-8 | SMART goals? P0/P1 priority levels? Success metrics defined? |
| **User Personas** | 0-5 | 1-2 personas with specific use cases? Names and contexts? |
| **Technical Specs** | 0-5 | Architecture considerations? Integration points? Data models? |

**Scoring Guide:**
- 7/7 Problem: Specific metrics, business impact quantified
- 8/8 Goals: SMART format, priority levels, measurable
- 5/5 Personas: Named personas with scenarios
- 5/5 Technical: Architecture diagram or description

---

### Category C: Implementation Clarity (30 points)

| Criterion | Points | What to Check |
|-----------|--------|---------------|
| **Functional Requirements** | 0-10 | FR codes (FR-001, FR-002)? P0/P1/P2 priorities? Acceptance criteria in Given-When-Then? |
| **Non-Functional Requirements** | 0-5 | Security, performance, reliability, scalability covered? |
| **Architecture** | 0-10 | System diagram? Data flow? Component interactions? API contracts? |
| **Phased Implementation** | 0-5 | Clear phases? Time estimates? Deliverables per phase? |

**Scoring Guide:**
- 10/10 FRs: Every requirement has code, priority, acceptance criteria
- 5/5 NFRs: Security + performance + at least one other
- 10/10 Architecture: Visual diagram + written description
- 5/5 Phases: 2-4 phases with clear deliverables

---

### Category D: Completeness (20 points)

| Criterion | Points | What to Check |
|-----------|--------|---------------|
| **Risk Assessment** | 0-5 | Top 3-5 risks identified? Mitigation strategies? |
| **Dependencies** | 0-3 | External and internal dependencies listed? |
| **Examples** | 0-7 | Code snippets, API examples, prompt templates for complex requirements? |
| **Documentation Quality** | 0-5 | Professional formatting? Table of contents for long PRDs? Glossary if needed? |

**Scoring Guide:**
- 5/5 Risks: 3+ risks with mitigations
- 3/3 Dependencies: Both internal and external
- 7/7 Examples: Code/API examples for complex features
- 5/5 Quality: Clean formatting, no typos, professional tone

---

## Step 3: Generate Score Report

Output format:

```
## PRD Score Report: [PRD Title]

### Overall Score: XX/100 ([Grade])

Grade Scale:
- 90-100: A+ (Excellent - Ready for AI implementation)
- 80-89: A (Good - Minor gaps, usable)
- 70-79: B (Acceptable - Some optimization needed)
- 60-69: C (Needs Work - Significant gaps)
- <60: D (Major Revision Required)

---

### Category Breakdown

| Category | Score | Max | Notes |
|----------|-------|-----|-------|
| A. AI-Specific Optimization | XX | 25 | [brief note] |
| B. Traditional PRD Core | XX | 25 | [brief note] |
| C. Implementation Clarity | XX | 30 | [brief note] |
| D. Completeness | XX | 20 | [brief note] |

---

### Detailed Scores

#### A. AI-Specific Optimization (XX/25)
- Sequential Phases: X/10 - [assessment]
- Explicit Non-Goals: X/8 - [assessment]
- Structured Format: X/7 - [assessment]

#### B. Traditional PRD Core (XX/25)
- Problem Statement: X/7 - [assessment]
- Goals & Metrics: X/8 - [assessment]
- User Personas: X/5 - [assessment]
- Technical Specs: X/5 - [assessment]

#### C. Implementation Clarity (XX/30)
- Functional Requirements: X/10 - [assessment]
- Non-Functional Requirements: X/5 - [assessment]
- Architecture: X/10 - [assessment]
- Phased Implementation: X/5 - [assessment]

#### D. Completeness (XX/20)
- Risk Assessment: X/5 - [assessment]
- Dependencies: X/3 - [assessment]
- Examples: X/7 - [assessment]
- Documentation Quality: X/5 - [assessment]

---

### Top 3 Improvement Recommendations

1. **[Highest Impact Fix]**
   - Current: [what's missing/weak]
   - Recommendation: [specific action]
   - Impact: +X points

2. **[Second Priority]**
   - Current: [what's missing/weak]
   - Recommendation: [specific action]
   - Impact: +X points

3. **[Third Priority]**
   - Current: [what's missing/weak]
   - Recommendation: [specific action]
   - Impact: +X points

---

### Verdict

[1-2 sentence summary of PRD quality and readiness for AI implementation]
```

---

## Step 4: Offer Improvements

After scoring, offer to help:

```
Would you like me to:
1. **Revise the PRD** - Apply the top recommendations
2. **Add missing sections** - Generate specific missing content
3. **Reformat for AI** - Convert to AI-optimized structure
4. **Export score** - Save this report to a file
```

---

## Example Interaction

**User:** Score this PRD: docs/auth-prd.md

**Claude:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - PRD Scoring Mode
📊 Evaluating PRD: docs/auth-prd.md

Reading PRD content...
```

*[Reads file, evaluates against framework]*

```
## PRD Score Report: User Authentication System

### Overall Score: 72/100 (B)

| Category | Score | Max |
|----------|-------|-----|
| A. AI-Specific Optimization | 15 | 25 |
| B. Traditional PRD Core | 22 | 25 |
| C. Implementation Clarity | 20 | 30 |
| D. Completeness | 15 | 20 |

### Top 3 Improvement Recommendations

1. **Add Non-Goals Section** (+8 points)
   - Current: No explicit boundaries defined
   - Recommendation: Add "Non-Goals" section with 3+ explicit exclusions
   - Impact: Prevents AI scope creep

2. **Add FR Codes and Acceptance Criteria** (+6 points)
   - Current: Requirements listed as bullets without codes
   - Recommendation: Convert to FR-001 format with Given-When-Then
   - Impact: AI can track and verify each requirement

3. **Add Architecture Diagram** (+5 points)
   - Current: Text description only
   - Recommendation: Add Mermaid diagram showing auth flow
   - Impact: Visual clarity for implementation

Would you like me to apply these improvements?
```

---

## Quality Gates

**Scoring is NOT complete until:**

1. ✅ All 4 categories evaluated
2. ✅ Each sub-criterion scored with justification
3. ✅ Top 3 recommendations provided with point impact
4. ✅ Clear verdict on AI-readiness

**If PRD is <70 points:**
- Strongly recommend revision before implementation
- Offer to help improve specific sections
