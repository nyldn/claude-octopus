# Output Format Standard

This document defines the standard for specifying output formats in Claude Octopus skills.

## Why Strict Output Formats?

1. **Consistency** - Users know what to expect
2. **Parseability** - Outputs can be programmatically processed
3. **Quality** - Reduces variance in multi-agent synthesis
4. **Training** - LLMs follow explicit formats better than vague guidelines

---

## The Template Pattern

Every skill that produces structured output SHOULD include:

```markdown
## Output Format

You MUST return your [analysis/output/response] in this exact format:

```markdown
# [Title Section]

## [Section 1 Name]
[Description of what goes here]

## [Section 2 Name]
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| [data]   | [data]   | [data]   |

## [Section 3 Name]
- [ ] [Checklist item format]
- [ ] [Another item]

[Continue with all required sections...]
```

**Required sections:**
- [List which sections are mandatory]

**Optional sections:**
- [List which can be omitted]
```

---

## Format Strictness Levels

### Level 1: Rigid Template (MUST)

Use for outputs that need to be parsed or compared:

```markdown
You MUST return in this exact format:
```

Examples:
- PRD documents (need consistent structure for scoring)
- Code review findings (need to track issues)
- Security audit reports (need to verify all sections present)

### Level 2: Structured Guidelines (SHOULD)

Use for outputs that benefit from structure but allow flexibility:

```markdown
Your response SHOULD follow this structure:
```

Examples:
- Research summaries (content varies by topic)
- Architecture recommendations (depends on context)
- Debugging analyses (varies by problem type)

### Level 3: Flexible Format (MAY)

Use for conversational or creative outputs:

```markdown
You MAY use this structure, adapting as needed:
```

Examples:
- Brainstorming sessions (creative flow)
- Thought partner conversations (dynamic)
- Decision support options (varies by complexity)

---

## Common Format Elements

### Headers and Sections

```markdown
# Main Title (H1 - one per document)

## Major Section (H2 - primary divisions)

### Subsection (H3 - within major sections)

#### Detail Level (H4 - rarely needed)
```

### Tables

```markdown
| Criterion | Option A | Option B | Option C |
|-----------|----------|----------|----------|
| Cost      | Low      | Medium   | High     |
| Risk      | Medium   | Low      | High     |
| Time      | 2 weeks  | 1 month  | 2 months |
```

### Checklists

```markdown
## Pre-Flight Checklist
- [ ] Required element 1
- [ ] Required element 2
- [x] Already completed item
```

### Status Indicators

```markdown
✅ Passed / Complete / Success
❌ Failed / Missing / Error
⚠️ Warning / Partial / Needs attention
🔍 Under investigation
🚧 In progress
```

### Code Blocks

```markdown
```python
# Language-tagged code blocks
def example():
    pass
```
```

### Callouts

```markdown
> **Note:** Important information

> **Warning:** Something to be careful about

> **Tip:** Helpful suggestion
```

---

## Skill-Specific Examples

### Example: Code Review Output Format

```markdown
## Output Format

You MUST return your review in this exact format:

```markdown
# Code Review: [File/Component Name]

## Summary
[2-3 sentence overview of the review findings]

## Critical Issues (Must Fix)
| # | Location | Issue | Recommendation |
|---|----------|-------|----------------|
| 1 | [file:line] | [description] | [fix] |

## Warnings (Should Fix)
| # | Location | Issue | Recommendation |
|---|----------|-------|----------------|
| 1 | [file:line] | [description] | [fix] |

## Suggestions (Consider)
- [Suggestion 1]
- [Suggestion 2]

## Positive Observations
- [What's done well]

## Pre-Merge Checklist
- [ ] All critical issues addressed
- [ ] Tests pass
- [ ] No new warnings introduced
```
```

### Example: Research Output Format

```markdown
## Output Format

You SHOULD structure your research in this format:

```markdown
# Research: [Topic]

## Executive Summary
[3-5 bullet points of key findings]

## Background
[Context and why this matters]

## Findings

### [Finding 1 Title]
**Source:** [where this came from]
**Reliability:** [High/Medium/Low]

[Details...]

### [Finding 2 Title]
[Continue pattern...]

## Synthesis
[What the combined findings tell us]

## Recommendations
1. [Actionable recommendation]
2. [Another recommendation]

## Sources
- [Source 1 with link]
- [Source 2 with link]
```
```

---

## Validation

Skills with Level 1 (MUST) formats should include validation criteria:

```markdown
## Format Validation

Your output is valid if:
- [ ] All required sections present
- [ ] Tables have correct column count
- [ ] Checklists use correct syntax
- [ ] No placeholder text remains ([example])
```

---

## Anti-Patterns

**DON'T do this:**

```markdown
## Output
Just write a summary of your findings.
```

**DO this instead:**

```markdown
## Output Format

You MUST return your summary in this format:

```markdown
## Summary
[2-3 sentences describing main findings]

## Key Points
- [Point 1]
- [Point 2]
- [Point 3]

## Next Steps
1. [Recommended action]
```
```

---

## Integration

When creating or updating a skill:

1. Determine strictness level (MUST/SHOULD/MAY)
2. Define all sections with descriptions
3. Include example values where helpful
4. Add validation criteria for Level 1 formats
5. Test that outputs match the format

---

## Related Documentation

- [ASCII-DIAGRAM-STANDARD.md](./ASCII-DIAGRAM-STANDARD.md) - Workflow diagrams
- [ERROR-HANDLING-STANDARD.md](./ERROR-HANDLING-STANDARD.md) - Error scenarios
- [PLUGIN-ARCHITECTURE.md](./PLUGIN-ARCHITECTURE.md) - Skill structure
