---
command: deliver
description: "Delivery phase - Review, validate, and test with multi-AI quality assurance"
aliases:
  - ink
  - review-phase
---

# Deliver - Delivery Phase ✅

**Part of Double Diamond: DELIVER** (convergent thinking)

Review, validate, and test using external CLI providers.

## Usage

```bash
/co:deliver        # Delivery phase
```

## Natural Language Examples

Just describe what you want to validate:

```
"Review the authentication code for security"
"Validate the caching implementation"
"Test the notification system"
"Quality check the API endpoints"
```

## What This Phase Does

The **deliver** phase validates and reviews implementations using external CLI providers:

1. **🔴 Codex CLI** - Code quality, best practices, technical correctness
2. **🟡 Gemini CLI** - Security audit, edge cases, user experience
3. **🔵 Claude (You)** - Synthesis and final validation report

This is the **convergent** phase - we ensure the solution meets quality standards before delivery.

## Quality Checks

The deliver phase includes:
- **Security audit** - OWASP compliance, vulnerability detection
- **Code quality** - Best practices, maintainability, readability
- **Edge cases** - Error handling, boundary conditions
- **Performance** - Efficiency, scalability
- **User experience** - API design, error messages, documentation

## When to Use Deliver

Use deliver when you need:
- **Review**: "Review X" or "Code review Y"
- **Validation**: "Validate Z"
- **Testing**: "Test the implementation"
- **Quality Check**: "Check if X works correctly"
- **Verification**: "Verify the implementation of Y"
- **Issue Finding**: "Find issues in Z"

**Don't use deliver for:**
- Implementation tasks (use develop phase)
- Research tasks (use discover phase)
- Requirement definition (use define phase)

## Part of the Full Workflow

Deliver is phase 4 of 4 in the embrace (full) workflow:
1. Discover
2. Define
3. Develop
4. **Deliver** ← You are here

To run all 4 phases: `/co:embrace`
