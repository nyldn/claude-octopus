---
name: prd-score
description: Score an existing PRD against the 100-point AI-optimization framework
arguments:
  - name: file
    description: Path to the PRD file to score (relative or absolute)
    required: true
---

## STOP - DO NOT INVOKE /skill OR Skill() AGAIN

This command is already executing. The PRD file to score is: **$ARGUMENTS.file**

## Instructions

Score the PRD against the 100-point AI-optimization framework.

### Step 1: Load the PRD

Read the file at `$ARGUMENTS.file` using the Read tool.

### Step 2: Evaluate Against Framework

Score each category:

#### Category A: AI-Specific Optimization (25 points)
- Sequential Phases: 0-10 pts (phases ordered by dependencies, each 5-15 min work)
- Explicit Non-Goals: 0-8 pts (dedicated Non-Goals section with explicit boundaries)
- Structured Format: 0-7 pts (FR codes, consistent headings, Given-When-Then criteria)

#### Category B: Traditional PRD Core (25 points)
- Problem Statement: 0-7 pts (quantified pain points, metrics)
- Goals & Metrics: 0-8 pts (SMART goals, P0/P1 priorities)
- User Personas: 0-5 pts (named personas with scenarios)
- Technical Specs: 0-5 pts (architecture, integrations, data models)

#### Category C: Implementation Clarity (30 points)
- Functional Requirements: 0-10 pts (FR codes, P0/P1/P2, acceptance criteria)
- Non-Functional Requirements: 0-5 pts (security, performance, reliability)
- Architecture: 0-10 pts (diagrams, data flow, API contracts)
- Phased Implementation: 0-5 pts (clear phases, time estimates, deliverables)

#### Category D: Completeness (20 points)
- Risk Assessment: 0-5 pts (3-5 risks with mitigations)
- Dependencies: 0-3 pts (external and internal)
- Examples: 0-7 pts (code snippets, API examples)
- Documentation Quality: 0-5 pts (formatting, ToC, glossary)

### Step 3: Generate Score Report

Output:
```
## PRD Score Report: [PRD Title]

### Overall Score: XX/100 ([Grade])

Grade Scale: A+ (90-100), A (80-89), B (70-79), C (60-69), D (<60)

| Category | Score | Max |
|----------|-------|-----|
| A. AI-Specific Optimization | XX | 25 |
| B. Traditional PRD Core | XX | 25 |
| C. Implementation Clarity | XX | 30 |
| D. Completeness | XX | 20 |

### Top 3 Improvement Recommendations
1. [Highest impact fix] - +X points
2. [Second priority] - +X points
3. [Third priority] - +X points

### Verdict
[1-2 sentence summary of PRD quality and AI-readiness]
```

### Step 4: Offer Improvements

After scoring, offer:
1. Revise the PRD - Apply top recommendations
2. Add missing sections - Generate specific missing content
3. Reformat for AI - Convert to AI-optimized structure
4. Export score - Save report to a file

**BEGIN NOW - read and score the PRD at: $ARGUMENTS.file**
