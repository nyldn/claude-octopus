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

## Instructions

Create an AI-optimized PRD following this workflow:

### Phase 1: Research (use web search for external topics)
- Use `mcp_websearch_web_search_exa` for external services/technologies
- Use `librarian` agent for documentation lookup
- Do NOT use `explore` agent for external topics (it only searches local files)

### Phase 2: Generate PRD with these sections
1. Executive Summary
2. Problem Statement (quantified)
3. Goals & Metrics (SMART, P0/P1)
4. Non-Goals (explicit boundaries)
5. User Personas
6. Functional Requirements (FR-001 format, P0/P1/P2)
7. Implementation Phases (dependency-ordered)
8. Risks & Mitigations

### Phase 3: Self-Score (100-point framework)
- AI-Specific Optimization: 25 pts
- Traditional PRD Core: 25 pts  
- Implementation Clarity: 30 pts
- Completeness: 20 pts

### Phase 4: Save the PRD
Write to the filename specified by user, or generate one based on feature name.

**BEGIN NOW - research and create the PRD for: $ARGUMENTS.feature**
