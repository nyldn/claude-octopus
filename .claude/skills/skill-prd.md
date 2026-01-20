---
name: skill-prd
description: |
  AI-optimized PRD writing workflow using multi-AI orchestration.
  Creates sequential, dependency-ordered PRDs that AI coding assistants can execute.
  Scores output against 100-point framework. Use /octo:prd <feature> to invoke.
---

# PRD Writing Skill

## Purpose

Create AI-optimized Product Requirements Documents that score 90+ on the 100-point PRD framework. Uses multi-AI orchestration to ensure comprehensive coverage and self-validates before delivery.

## When This Skill Activates

**Via command only** (to prevent recursive activation):
- `/octo:prd user authentication`
- `/octo:prd checkout flow redesign`
- `/octo:prd notification system`

Note: Natural language triggers removed due to recursive activation issues.

## Visual Indicator

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - PRD Writing Mode
📋 Creating AI-Optimized PRD: [Feature Name]

Providers:
🔴 Codex CLI - Technical requirements and architecture
🟡 Gemini CLI - User research and market context
🔵 Claude - Structure, synthesis, and quality scoring
```

---

## PRD Creation Workflow

### Phase 1: Discovery & Context (5 min)

**Gather information before writing:**

1. **Clarify the feature scope**
   - What problem does this solve?
   - Who are the users?
   - What's explicitly OUT of scope?

2. **Identify existing context**
   - Check for existing docs in `docs/`, `specs/`, `requirements/`
   - Look for related code that hints at technical constraints
   - Find any user research or analytics data

3. **Determine PRD depth**
   - Simple feature (< 1 week work) → Lightweight PRD (40-60 lines)
   - Medium feature (1-4 weeks) → Standard PRD (100-200 lines)
   - Complex system (> 1 month) → Comprehensive PRD (300+ lines)

**Ask if unclear:**
```
I'm preparing to write a PRD for [feature]. Before I start:

1. **Scope**: Is this a new feature, enhancement, or system? 
2. **Users**: Who are the primary users?
3. **Timeline**: Rough timeline expectation?
4. **Constraints**: Any known technical or business constraints?
5. **Non-goals**: Anything explicitly out of scope?
```

---

### Phase 2: Multi-AI Research (Required for complex PRDs)

**CRITICAL: Choose the right research approach based on topic:**

#### For EXTERNAL topics (new technologies, third-party services):
Use `librarian` agent and web search - NOT explore (which only searches local files).

```bash
# Example: PRD for WordPress on Pressable
background_task(agent="librarian", prompt="Research Pressable WordPress hosting: features, SSH access, WP-CLI support, deployment workflows, limitations")
background_task(agent="librarian", prompt="Research Claude Code capabilities for PHP/WordPress development: file editing, terminal access, MCP integrations")

# Use web search for current documentation
mcp_websearch_web_search_exa(query="Pressable WordPress hosting developer documentation API")
mcp_websearch_web_search_exa(query="Claude Code WordPress development workflow best practices")
```

#### For INTERNAL topics (existing codebase features):
Use `explore` agent to find existing patterns.

```bash
# Example: PRD for enhancing existing auth system
background_task(agent="explore", prompt="Find existing authentication patterns in this codebase")
background_task(agent="librarian", prompt="Research OAuth 2.0 best practices for [framework]")
```

**Synthesis questions:**
- What technical approaches exist?
- What are common pitfalls?
- What do successful implementations include?
- What are the platform/service limitations?

---

### Phase 3: PRD Generation

**Use the product-writer persona with this structure:**

#### Required Sections (Minimum Viable PRD)

1. **Executive Summary** - Vision + key benefits
2. **Problem Statement** - Quantified pain points
3. **Goals & Metrics** - SMART goals with P0/P1 metrics
4. **Non-Goals** - Explicit boundaries (CRITICAL for AI)
5. **User Personas** - 1-2 personas with use cases
6. **Functional Requirements** - FR codes, priorities, acceptance criteria
7. **Implementation Phases** - Sequential, dependency-ordered
8. **Risks** - Top 3-5 risks with mitigation

#### Extended Sections (Comprehensive PRD)

9. **Non-Functional Requirements** - Security, performance, reliability
10. **Technical Architecture** - Diagrams and data models
11. **Dependencies** - External and internal
12. **Appendices** - Glossary, references, prompt templates

---

### Phase 4: Self-Scoring

**Before delivering, score against the 100-point framework:**

#### Scoring Checklist

**AI-Specific Optimization (25 pts)**
- [ ] Sequential phases with dependencies (0-10)
- [ ] Explicit non-goals section (0-8)
- [ ] Structured, parseable format (0-7)

**Traditional PRD Core (25 pts)**
- [ ] Quantified problem statement (0-7)
- [ ] SMART goals with metrics (0-8)
- [ ] User personas with use cases (0-5)
- [ ] Technical specifications (0-5)

**Implementation Clarity (30 pts)**
- [ ] FR codes with P0/P1/P2 priorities (0-10)
- [ ] NFRs covering security/performance (0-5)
- [ ] Architecture diagram or description (0-10)
- [ ] Phased implementation plan (0-5)

**Completeness (20 pts)**
- [ ] Risk assessment with mitigation (0-5)
- [ ] Dependencies identified (0-3)
- [ ] Examples and templates (0-7)
- [ ] Professional documentation quality (0-5)

**Score Interpretation:**
- 90-100: Excellent - Ready for AI implementation
- 80-89: Good - Minor gaps, usable
- 70-79: Acceptable - Some AI optimization needed
- <70: Needs revision - Add missing sections

---

### Phase 5: Delivery

**Output location:**
```
~/.claude-octopus/results/[session]/prd-[feature-name]-[timestamp].md
```

**Delivery message:**
```
📋 **PRD Complete: [Feature Name]**

**Self-Score:** [XX]/100 ([Grade])

**Sections:**
- ✅ Executive Summary
- ✅ Problem Statement  
- ✅ Goals & Metrics (P0: 3, P1: 2)
- ✅ Non-Goals (4 explicit boundaries)
- ✅ Personas (2 defined)
- ✅ Functional Requirements (12 total: 4 P0, 5 P1, 3 P2)
- ✅ Implementation Phases (3 phases)
- ✅ Risks (5 identified)

**Ready for:** AI-assisted implementation

**Saved to:** [path]
```

---

## PRD Templates by Complexity

### Lightweight PRD (Simple Feature)

```markdown
# PRD: [Feature Name]

## Summary
[2-3 sentences: what and why]

## Problem
[Current pain point with impact]

## Goal
[Single SMART goal with metric]

## Non-Goals
- [Explicit boundary 1]
- [Explicit boundary 2]

## Requirements

**FR-001: [Core Requirement]** (P0)
[Description]
- Given [context], when [action], then [result]

**FR-002: [Secondary Requirement]** (P1)
[Description]
- Given [context], when [action], then [result]

## Phases
1. **Phase 1** (Week 1): [Deliverable]
2. **Phase 2** (Week 2): [Deliverable]

## Risks
- [Risk]: [Mitigation]
```

### Standard PRD (Medium Feature)

Use the full template from product-writer persona, sections 1-9.

### Comprehensive PRD (Complex System)

Use the full template from product-writer persona, all 12+ sections, with:
- Multiple architecture diagrams
- Detailed data models
- API specifications
- Prompt template library
- Extensive examples

---

## Integration with Claude Octopus Workflows

### From Research to PRD

```
User: "octo research authentication patterns"
→ Discover phase generates research synthesis

User: "Now write a PRD based on that research"
→ PRD skill uses research output as input
```

### From PRD to Implementation

```
User: "Create implementation todos from this PRD"
→ Extract phases and requirements into todo list
→ Each FR becomes a trackable task
```

### PRD Review with Debate

```
User: "octo debate this PRD from PM, Engineering, and QA perspectives"
→ Multi-AI critique identifies gaps
→ Revise PRD based on feedback
```

---

## Quality Gates

**PRD is NOT complete until:**

1. ✅ Self-score calculated and reported
2. ✅ All P0 requirements have acceptance criteria
3. ✅ Non-Goals section has ≥2 explicit boundaries
4. ✅ Implementation phases are dependency-ordered
5. ✅ At least one example provided for complex requirements

**If score < 80:**
- Identify lowest-scoring categories
- Add missing sections
- Re-score before delivery

---

## Example Interaction

**User:** Write a PRD for adding dark mode to our app

**Claude:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - PRD Writing Mode
📋 Creating AI-Optimized PRD: Dark Mode Feature

Before I write the PRD, a few quick questions:

1. **Scope**: Is this system-wide dark mode or specific sections?
2. **Users**: All users, or premium feature?
3. **Timeline**: Target release timeframe?
4. **Constraints**: Any design system or accessibility requirements?
5. **Non-goals**: Should I exclude things like scheduled switching or per-page themes?
```

**User:** System-wide, all users, Q2 release, must meet WCAG AA contrast. Exclude scheduled switching.

**Claude:** [Generates full PRD with self-score]

```
📋 **PRD Complete: Dark Mode**

**Self-Score:** 92/100 (A+)

**Sections:**
- ✅ Executive Summary
- ✅ Problem Statement (eye strain, user requests)
- ✅ Goals & Metrics (P0: 2, P1: 3)
- ✅ Non-Goals (3 boundaries including scheduled switching)
- ✅ Personas (2: power user, accessibility user)
- ✅ Functional Requirements (8 total)
- ✅ NFRs (WCAG AA compliance)
- ✅ Implementation Phases (3 phases, 6 weeks)
- ✅ Risks (4 identified)

**Ready for:** AI-assisted implementation
```
