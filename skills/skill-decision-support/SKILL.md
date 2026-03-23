---
name: skill-decision-support
version: 1.0.0
description: "Present 2-4 options with trade-off analysis, effort/risk/timeline comparison, and a reasoned recommendation. Use when: user says 'fix or provide options', 'give me options', 'what are my options', 'help me decide', 'show alternatives', or needs to choose between approaches."
---

# Decision Support & Options Presentation

**Core principle:** Understand context, generate 2-4 distinct options, analyze trade-offs, present with comparison table, recommend with reasoning.

---

## When to Use

**Activate when user:** asks for options, says "fix or provide options", needs help deciding between approaches, wants different ways to solve a problem.

**Do NOT use for:** general research (use flow-probe), implementation work (use flow-tangle), simple yes/no questions, already-decided approaches.

---

## The Process

### Phase 1: Context Understanding

Gather the decision context: what needs deciding, why it matters, constraints (time, resources, compatibility), and current state. Use AskUserQuestion if needed for must-haves, deal-breakers, and timeline.

### Phase 2: Generate Options

Generate 2-4 **distinct** options (not minor variations):

| Option Type | When to Include |
|-------------|-----------------|
| **Conservative** | Low risk, proven approach |
| **Moderate** | Balanced risk/reward |
| **Innovative** | Higher risk, potentially better outcome |
| **Minimal** | Simplest possible solution |

Do not generate options that violate stated constraints or are clearly inferior.

---

### Phase 3: Trade-off Analysis

For each option, provide: description (1-2 sentences), pros, cons, effort (Low/Med/High), risk (Low/Med/High), reversibility, and "best for" scenario.

### Phase 4: Present Options

Structure the presentation as:

1. **Decision title and context** (one sentence)
2. **Each option** with: what it is, pros/cons, implementation overview, timeline, risk level
3. **Mark recommendation** with ⭐ or "(Recommended)"
4. **Quick Comparison table** with effort, risk, reversibility, timeline, best-for columns
5. **Recommendation** with 2-3 concrete reasons
6. **"Which option would you like to proceed with?"**

Guidelines: limit to 2-4 options, be honest about cons, use consistent structure across options.

---

### Phase 5: Support the Choice

After user chooses: confirm selection, outline next steps, and begin implementation or gather more details. If user asks for a deep dive on a specific option, provide detailed implementation steps and issue/mitigation pairs.

---

## Integration with Other Skills

- **flow-probe**: Research options thoroughly before presenting
- **flow-tangle**: Implement the chosen option
- **skill-debug**: Present fix options when bugs have multiple solutions

---

## Best Practices

1. **Quantify** timelines and effort (use hours/days, not "quick"/"a while")
2. **Be honest about unknowns** - flag estimation uncertainty
3. **Provide escape hatch** - offer to research more, combine options, or prototype
4. **Ask about constraints** before presenting: timeline, resources, risk tolerance, reversibility

---

## Quick Reference

| User Request | Action |
|--------------|--------|
| "fix or provide options" | Assess if fix obvious; if not, present options |
| "what are my options" | Understand context, generate 2-4 options with trade-offs |
| "help me decide" | Clarify factors, compare, recommend with reasoning |
| "show alternatives" | Generate alternatives with pros/cons comparison |
