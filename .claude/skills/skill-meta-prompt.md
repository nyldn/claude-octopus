---
name: skill-meta-prompt
aliases:
  - meta-prompt
  - prompt-generator
  - prompt-optimizer
  - prompt-engineering
description: Generate optimized prompts using proven techniques
trigger: |
  Use PROACTIVELY when user wants to:
  - "create a prompt for", "write a prompt for"
  - "optimize this prompt", "improve this prompt"
  - "generate a meta-prompt", "help me write a prompt"
  - "prompt engineering", "better prompt"
  - "create instructions for [task]"
  
  DO NOT use for:
  - Direct task execution (just do the task)
  - Simple questions (just answer)
  - Code generation (use development skills)
---

# Meta-Prompt Generator Skill

## Overview

Generate well-structured, verifiable prompts for any use case. Applies proven meta-prompting techniques to minimize hallucination and maximize effectiveness.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       META-PROMPT GENERATION                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Phase 1: Requirement Gathering                                             │
│       → Understand the primary goal/role                                    │
│       → Clarify expected outputs                                            │
│       → Identify accuracy requirements                                      │
│       ↓                                                                     │
│  Phase 2: Task Analysis                                                     │
│       → Apply Technique 1: Task Decomposition                               │
│       → Identify if complex enough for subtasks                             │
│       → Map dependencies between subtasks                                   │
│       ↓                                                                     │
│  Phase 3: Expert Assignment                                                 │
│       → Apply Technique 5: Specialized Experts                              │
│       → Assign personas to subtasks                                         │
│       → Apply Technique 2: Fresh Eyes Review                                │
│       ↓                                                                     │
│  Phase 4: Verification Design                                               │
│       → Apply Technique 3: Iterative Verification                           │
│       → Build in checking steps                                             │
│       → Apply Technique 4: No Guessing                                      │
│       ↓                                                                     │
│  Phase 5: Prompt Assembly                                                   │
│       → Structure: Role, Context, Instructions, Constraints, Format         │
│       → Add verification hooks                                              │
│       → Include uncertainty disclaimers                                     │
│       ↓                                                                     │
│  Phase 6: Output & Iteration                                                │
│       → Present generated prompt                                            │
│       → Offer refinement                                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## The Five Techniques

### Technique 1: Task Decomposition

**What:** Break complex tasks into smaller, manageable subtasks.

**When to use:**
- Task has multiple distinct steps
- Different expertise needed for different parts
- Risk of getting lost in complexity

**How to apply:**
1. List all components of the task
2. Identify dependencies (what must happen first)
3. Group related components
4. Order by logical sequence

**Example:**
```
Task: "Create a technical blog post about OAuth 2.0"

Decomposition:
1. Research Phase
   - Gather OAuth 2.0 specifications
   - Find common implementation examples
   - Identify security best practices
   
2. Structure Phase
   - Outline main sections
   - Plan code examples
   - Design diagrams/visuals
   
3. Writing Phase
   - Write introduction
   - Write technical sections
   - Write conclusion/CTA
   
4. Review Phase
   - Technical accuracy check
   - Code example testing
   - Readability review
```

---

### Technique 2: Fresh Eyes Review

**What:** Use different "experts" for creation vs. validation. Never use the same expert to both create and verify.

**When to use:**
- Output needs to be accurate
- Risk of blind spots from creator
- Quality assurance is critical

**How to apply:**
1. Assign Creator Expert for initial work
2. Assign different Reviewer Expert for validation
3. Reviewer should not have seen creation process
4. Loop back to Creator if issues found

**Example:**
```
Creator: "Expert Technical Writer" produces article
Reviewer: "Expert Security Engineer" verifies OAuth claims
Reviewer: "Expert Developer" tests code examples

NOT: Same expert writes AND reviews their own work
```

---

### Technique 3: Iterative Verification

**What:** Build explicit verification steps into the task, especially for error-prone outputs.

**When to use:**
- Mathematical calculations
- Code generation
- Factual claims
- Multi-step reasoning

**How to apply:**
1. After each significant output, add verification step
2. For calculations: "Now verify this by [alternative method]"
3. For code: "Test this code against [test cases]"
4. For claims: "Confirm this by [citing source]"

**Example:**
```
Step 1: Calculate discount price
Step 2: VERIFY - recalculate from opposite direction
Step 3: If mismatch, identify error and recalculate
Step 4: Only proceed when both methods match
```

---

### Technique 4: No Guessing

**What:** Never assume unverified facts. Disclaim uncertainty explicitly.

**When to use:**
- ALWAYS (this is a default behavior)
- Especially for: dates, statistics, quotes, technical specifications

**How to apply:**
1. If uncertain, say "I'm not certain about..."
2. If no data, say "I don't have information on..."
3. Ask for sources rather than inventing
4. Distinguish between "likely" and "confirmed"

**Disclaimer templates:**
```
"Note: This figure is approximate and should be verified."
"I don't have access to [specific data]. Please provide or verify."
"This is based on general patterns; your specific case may differ."
```

---

### Technique 5: Specialized Experts

**What:** Spawn domain-specific personas for complex subtasks.

**When to use:**
- Task requires specialized knowledge
- Different perspectives would improve quality
- Cross-functional work needed

**Available expert archetypes:**
| Expert | Use For |
|--------|---------|
| Expert Writer | Content, copy, documentation |
| Expert Mathematician | Calculations, proofs, statistics |
| Expert Python | Python code, data analysis |
| Expert Security | Security review, threat modeling |
| Expert Architect | System design, trade-offs |
| Expert Reviewer | Quality assurance, error-finding |
| Expert Strategist | Planning, prioritization |

**How to apply:**
```
"For this subtask, adopt the persona of Expert [X].
Your expertise includes [specific areas].
Focus exclusively on [your assigned task].
You have no memory of previous context—all needed information is below."
```

---

## Phase 1: Requirement Gathering

### Initial Prompt

```markdown
**Meta-Prompt Generator**

I'll help you create an effective, verifiable prompt.

**Questions:**

1. **What is the main goal?**
   What should this prompt help someone accomplish?

2. **What's the expected output?**
   (e.g., document, code, analysis, decision)

3. **How important is accuracy?**
   - Critical (factual, technical, or high-stakes)
   - Moderate (useful but not mission-critical)
   - Flexible (creative, exploratory)

4. **Any specific constraints?**
   (length, format, tone, tools available)
```

### Minimum Information Needed

- Primary goal (REQUIRED)
- Output type (REQUIRED)
- Accuracy requirements (can assume moderate)
- Constraints (optional, will use sensible defaults)

**If information is missing, ask ONE clarifying question at a time.**

---

## Phase 2-4: Analysis & Design

After gathering requirements, analyze internally:

### Task Complexity Assessment

| Complexity | Indicators | Approach |
|------------|------------|----------|
| **Simple** | Single step, one output | Direct prompt, no decomposition |
| **Moderate** | 2-3 steps, clear sequence | Light decomposition, one expert |
| **Complex** | 4+ steps, dependencies | Full decomposition, multiple experts |

### Expert Assignment Matrix

| Task Type | Creator Expert | Reviewer Expert |
|-----------|----------------|-----------------|
| Technical writing | Expert Writer | Expert Engineer |
| Code generation | Expert Developer | Expert Reviewer |
| Analysis | Expert Analyst | Expert Strategist |
| Creative | Expert Creative | Expert Editor |

### Verification Points

For the task, identify where verification is needed:

| Step | Risk | Verification Method |
|------|------|---------------------|
| [step] | [what could go wrong] | [how to verify] |

---

## Phase 5: Prompt Assembly

### Output Format

You MUST return the generated prompt in this exact format:

```markdown
# [Prompt Title]

## Role
[Short, direct role definition]
[Emphasize verification and uncertainty disclaimers]

## Context
[User's task and goals]
[Background information provided]
[Clarifications gathered]

## Instructions

### Phase 1: [First Phase Name]
1. [Step 1]
2. [Step 2]
3. **Verification:** [How to verify this phase]

### Phase 2: [Second Phase Name]
1. [Step 1]
2. [Step 2]
3. **Verification:** [How to verify this phase]

[Continue phases as needed...]

### Expert Assignments (if applicable)
- **[Expert Type]:** Handles [specific subtask]
- **[Reviewer Type]:** Validates [what they check]

## Constraints
- [Constraint 1]
- [Constraint 2]
- [Accuracy requirement: how to handle uncertainty]

## Output Format
[Specify exactly how the output should be structured]
[Include all required sections]

## Verification Checklist
Before considering complete:
- [ ] [Verification item 1]
- [ ] [Verification item 2]
- [ ] [Accuracy disclaimers added where needed]

## Examples (if provided)
[Context or examples from user]
```

---

## Phase 6: Output & Iteration

### Present the Prompt

```markdown
**Generated Meta-Prompt**

[The prompt in the format above]

---

**Techniques Applied:**
- ✓ Task Decomposition: [Yes/No, how]
- ✓ Fresh Eyes Review: [Yes/No, which experts]
- ✓ Iterative Verification: [Yes/No, where]
- ✓ No Guessing: [Where disclaimers needed]
- ✓ Specialized Experts: [Which ones assigned]

**Would you like me to:**
1. Refine any section
2. Add more verification steps
3. Adjust the complexity level
4. Execute this prompt now
```

---

## Example: Complete Meta-Prompt Generation

### User Request
"Create a prompt to help me write API documentation"

### Generated Prompt

```markdown
# API Documentation Generator

## Role
You are an Expert Technical Writer specializing in API documentation.
Your documentation will be reviewed by an Expert Developer for accuracy.
When uncertain about behavior, note "Verify with implementation" rather than guessing.

## Context
Creating comprehensive API documentation for developers.
Documentation should be usable without reading source code.

## Instructions

### Phase 1: API Discovery
1. List all endpoints with methods (GET, POST, etc.)
2. Document request/response schemas
3. Identify authentication requirements
4. **Verification:** Cross-reference with OpenAPI spec if available

### Phase 2: Documentation Writing
1. Write endpoint descriptions (what it does, not how)
2. Create request examples with all parameters
3. Create response examples for success and error cases
4. Document rate limits and constraints
5. **Verification:** Each example should be valid JSON/code

### Phase 3: Review Cycle
Expert Developer reviews for:
- Technical accuracy of examples
- Missing edge cases
- Unclear descriptions

### Expert Assignments
- **Expert Technical Writer:** Creates documentation prose
- **Expert Developer:** Validates examples and accuracy

## Constraints
- Use consistent terminology throughout
- Examples must be syntactically valid
- Note any undocumented or unclear behaviors
- Accuracy: Mark assumptions with "Assumed behavior - verify"

## Output Format
```markdown
# [Endpoint Name]

**Method:** [HTTP method]
**Path:** [/api/path]
**Auth:** [Required/Optional/None]

## Description
[What this endpoint does]

## Request
[Parameters, body schema, headers]

## Response
[Success and error responses with examples]

## Notes
[Rate limits, deprecation, related endpoints]
```

## Verification Checklist
- [ ] All endpoints documented
- [ ] All examples are valid
- [ ] Authentication clearly specified
- [ ] Error responses included
- [ ] Assumptions marked for verification
```

---

## Error Handling

### Unclear Requirements

```markdown
I need a bit more clarity to create an effective prompt.

**Specifically:**
[Question about the unclear part]

[Offer 2-3 options if applicable]
```

### Over-Complex Request

```markdown
This task has [N] distinct components. I recommend:

1. **Split into multiple prompts** - One per major component
2. **Simplify scope** - Focus on [core element] first
3. **Proceed as-is** - Full complexity, longer prompt

Which approach works best for you?
```

### Can't Apply Techniques

If techniques don't fit the task:

```markdown
ℹ️ **Note on Techniques**

This task is straightforward enough that some techniques
don't apply:

- Task Decomposition: Not needed (single step)
- Fresh Eyes: [Explain why/why not]
- Specialized Experts: Not needed (single domain)

The generated prompt focuses on clarity and verification instead.
```

---

## Integration

### With skill-content-pipeline
Generate prompts for content creation based on anatomy guides.

### With skill-thought-partner
Transform brainstorming insights into actionable prompts.

### With skill-prd
Enhance PRD generation with meta-prompting techniques.

### With flow-develop
Generate implementation prompts with built-in verification.

---

## The Bottom Line

```
Meta-prompt → Decompose → Assign experts → Build verification → Generate
Otherwise → Vague prompts → Hallucination → Unreliable output
```

**Structure breeds reliability. Verification breeds accuracy. Experts breed quality.**
