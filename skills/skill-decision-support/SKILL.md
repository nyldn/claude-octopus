---
name: skill-decision-support
description: "Present options with trade-offs for informed decision-making — use when choosing between approaches"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Decision Support & Options Presentation

## Overview

Structured approach to presenting options and alternatives with clear trade-offs, enabling informed decision-making.

**Core principle:** Understand context → Generate options → Analyze trade-offs → Present clearly → Support choice.


## When to Use

**Use this skill when user:**
- Asks for options or alternatives
- Says "fix or provide options"
- Needs help deciding between approaches
- Wants to see different ways to solve a problem
- Is uncertain about best path forward

**Do NOT use for:**
- General research ("what is X?") → use flow-probe
- Implementation work → use flow-tangle
- Simple yes/no questions
- Already-decided approaches


## The Process

### Phase 1: Context Understanding

#### Step 1: Understand the Decision Point

```markdown
**Decision Context:**

What needs to be decided: [the core question]
Why it matters: [impact of this decision]
Constraints: [time, resources, compatibility, etc.]
Current state: [what exists now]
```

#### Step 2: Gather Requirements

Use AskUserQuestion if needed to understand:
- Must-have requirements
- Nice-to-have features
- Deal-breakers
- Timeline constraints
- Budget/resource constraints

#### Step 3: Set the decision criteria before scoring

Choose criteria, scoring definitions and weights before evaluating the options.
Use the user's stated priorities. If priorities are missing, state the assumed
weights and the effect those assumptions may have. Weights must total 100%.
Keep the same criteria and weights for every option. Do not change them to
make a preferred option win; record any later revision and rescore all options.


### Phase 2: Generate Options

#### Step 1: Identify Viable Approaches

Generate 2-4 distinct options, including the status quo. Always include doing
nothing as the comparison baseline and state its cost, risks and consequences
of delay. If it violates a requirement, retain it for comparison and explain
why it is not viable. Do not assume that changing something is beneficial.

| Option Type | When to Include |
|-------------|-----------------|
| **Status quo / do nothing** | Always; include its ongoing cost and cost of delay |
| **Conservative** | Low risk, proven approach |
| **Moderate** | Balanced risk/reward |
| **Innovative** | Higher risk, potentially better outcome |
| **Minimal** | Simplest possible solution |

**Except for the required status-quo baseline, don't generate options that:**
- Violate stated constraints
- Are clearly inferior to others
- Are essentially the same with minor tweaks

#### Step 2: Research Each Option

For each option, understand:
- How it works
- What it requires
- What the outcome looks like
- What could go wrong


### Phase 3: Trade-off Analysis

For each option, analyze the trade-offs below, then score it against the criteria
and weights set in Phase 1. Show raw scores beside weighted scores and the total.
Label uncertain inputs and assumptions; do not invent measurements to fill a
scoring table. Choose the recommendation only after this analysis, with reasons
that refer to the user's requirements and the comparison baseline.

```markdown
### Option N: [Name]

**Description:**
[1-2 sentence description]

**Pros:**
- ✅ [Advantage 1]
- ✅ [Advantage 2]
- ✅ [Advantage 3]

**Cons:**
- ❌ [Disadvantage 1]
- ❌ [Disadvantage 2]
- ❌ [Disadvantage 3]

**Effort:** [Low/Medium/High]
**Risk:** [Low/Medium/High]
**Reversibility:** [Easy/Moderate/Difficult to undo]

**Best for:** [when this option makes sense]
```

#### Optional scenario stress test

For a decision that depends on uncertain assumptions, select the two drivers
with the most uncertainty and impact. Describe three or four plausible futures
and check how each option performs in each. Report which option holds up across
the futures and which assumptions would change the recommendation. Keep this
optional; do not add provider calls without the user's existing authorization.


### Phase 4: Present Options

#### Format for Presentation

Omit unused option sections and table columns when presenting fewer than four options.

```markdown
# Decision: [What needs to be decided]

**Context:** [Brief summary of why this decision is needed]


## Option 1: [Option name]

**What it is:**
[Clear explanation in 1-2 sentences]

**Pros:**
- ✅ [Pro 1]
- ✅ [Pro 2]
- ✅ [Pro 3]

**Cons:**
- ❌ [Con 1]
- ❌ [Con 2]

**Implementation:**
[Brief overview of what's involved]

**Timeline:** [estimate]
**Risk Level:** Low/Medium/High


## Option 2: [Option name]

[Same structure as Option 1]


## Option 3: [Option name, if needed]

[Same structure as Option 1]


## Option 4: [Option name, if needed]

[Same structure as Option 1]


## Quick Comparison

| Criteria | Option 1 | Option 2 | Option 3 | Option 4 |
|----------|----------|----------|----------|----------|
| Effort | [level] | [level] | [level] | [level] |
| Risk | [level] | [level] | [level] | [level] |
| Reversible | [yes/no] | [yes/no] | [yes/no] | [yes/no] |
| Timeline | [time] | [time] | [time] | [time] |
| Best for | [scenario] | [scenario] | [scenario] | [scenario] |

## Criteria and scores

| Criterion | Weight | Option 1 raw / weighted | Option 2 raw / weighted | Option 3 raw / weighted | Option 4 raw / weighted |
|-----------|--------|-------------------------|-------------------------|-------------------------|-------------------------|
| [Criterion fixed before scoring] | [percentage] | [raw / weighted] | [raw / weighted] | [raw / weighted] | [raw / weighted] |
| **Total** | **100%** | [weighted total] | [weighted total] | [weighted total] | [weighted total] |

[State the scoring scale, evidence and uncertainty. Include the status quo as
one of the options above and explain its ongoing cost and the cost of delay.]


## Recommendation

**I recommend Option [N]: [Name]**

[Select N from the completed analysis. No option is recommended by default.]

**Why:**
1. [Reason 1]
2. [Reason 2]
3. [Reason 3]

**This option is best because:** [summary of key advantage relative to context]


**Which option would you like to proceed with?**
```

#### Guidelines for Presentation

1. **Mark the analyzed recommendation clearly**, after comparing every option.
2. **Limit to 2-4 options including the status quo** (too many = decision paralysis)
3. **Be honest about cons** (don't oversell any option)
4. **Make comparison easy** (use consistent structure)
5. **Support with reasoning** (explain why recommendation makes sense)


### Phase 5: Support the Choice

After user chooses:

```markdown
✅ **Proceeding with Option [N]: [Name]**

**Next steps:**
1. [Step 1]
2. [Step 2]
3. [Step 3]

**I'll now [begin implementation / gather more details / create plan].**
```

If user asks for more info on a specific option:

```markdown
**Deep dive on Option [N]:**

**How it works:**
[Detailed explanation]

**Implementation steps:**
1. [Detailed step 1]
2. [Detailed step 2]
...

**Potential issues and mitigations:**
- Issue: [potential problem]
  Mitigation: [how to handle it]

**Would you like to proceed with this option?**
```


## Common Patterns

### Pattern 1: "Fix or Provide Options"

```
User: "The auth system is broken. Fix or provide options."

Response structure:
1. Assess: Is the fix obvious or are there choices?
2. If obvious: Present the fix + ask for confirmation
3. If choices: Present options with trade-offs

Example:

I can see the auth issue. Here are your options:

**Option 1: Quick Fix**
- Patch the current JWT validation
- Pros: Fast, low risk
- Cons: Doesn't address underlying architecture

**Option 2: Comprehensive Refactor**
- Rebuild auth with better patterns
- Pros: Long-term solution
- Cons: Takes longer, more testing needed

**Option 3: Keep the current implementation**
- State the ongoing cost, risk and consequences of delaying the fix.

Recommend an option only after comparing these against the agreed criteria.

**Which approach fits your timeline?**
```

### Pattern 2: "What Are My Options"

```
User: "I need to add caching. What are my options?"

Response structure:
1. Understand requirements (what needs caching, scale, etc.)
2. Generate 2-4 options including keeping the API uncached
3. Present with trade-offs
4. Recommend based on their context

Example:

For caching your API responses, here are the main options:

**Option 1: In-Memory Cache (Node-cache)**
- Best for: Single-server setup
- Pros: Simple, fast, no external dependencies
- Cons: Lost on restart, doesn't scale across servers

**Option 2: Redis**
- Best for: Multi-server or persistence needed
- Pros: Persistent, distributed, feature-rich
- Cons: Requires Redis server, more complex

**Option 3: CDN Caching (Cloudflare/Fastly)**
- Best for: Static/semi-static content
- Pros: Global distribution, handles scale
- Cons: Less control, costs, public content only

**Option 4: Keep the API uncached**
- State the current operating cost, latency and consequences of delaying a change.

**After scoring against the agreed criteria, recommend Option [N] because [evidence].**
Which would you like to use?
```

### Pattern 3: "Help Me Decide"

```
User: "Should I use TypeScript or stick with JavaScript? Help me decide."

Response structure:
1. Clarify decision factors (team size, project scope, timeline)
2. Agree on criteria, scoring definitions and weights totaling 100% before evaluating either option
3. Compare the alternatives, including the current setup and its cost of delay, with raw and weighted scores
4. Recommend after comparing the weighted totals and checking constraints
5. Support whatever they choose

Example:

Let me help you decide between TypeScript and JavaScript.

Before evaluating either option, agree on the criteria, scoring definitions and
weights. Keep those weights fixed across both options.

**Option 1: TypeScript**
Pros: Type safety, better tooling, catches errors early
Cons: Learning curve, build step, more setup
Best for: Larger teams, long-term projects, complex domains

**Option 2: Keep JavaScript, the current setup**
Pros: Simpler, no build step, familiar to all devs
Cons: Runtime errors, less IDE support, harder to refactor
Best for: Small projects, prototypes, simple applications
Ongoing cost and cost of delay: [Quantify current maintenance costs and any consequences of delaying migration. State when no change is needed.]

**Comparison using the criteria agreed before evaluation**

| Criterion and scoring definition | Weight | TypeScript raw / weighted | JavaScript raw / weighted |
|---|---|---|---|
| [Agreed criterion and score meanings] | [weight %] | [raw score] / [weighted contribution] | [raw score] / [weighted contribution] |
| **Total** | **100%** | [weighted total] | [weighted total] |

Repeat the criterion row for every agreed criterion. Weighted contribution is
the raw score multiplied by the percentage weight divided by 100. Label
uncertain inputs and explain any constraint that the totals do not capture.

**After comparing against the agreed criteria, recommend Option [N] because [evidence].**

Which option would you like to proceed with?
```


## Integration with Other Skills

### With flow-probe

```
Need to research options thoroughly?
→ Use flow-probe to gather information
→ Use skill-decision-support to present findings as options
```

### With flow-tangle

```
User chose an option?
→ Use flow-tangle to implement the chosen approach
```

### With skill-debug

```
Bug could be fixed multiple ways?
→ Use skill-decision-support to present fix options
→ Use skill-debug to implement chosen fix systematically
```


## Best Practices

### 1. Tailor to User's Needs

**Ask about constraints:**
```markdown
Before presenting options, I need to understand:
- Timeline: How urgent is this?
- Resources: What's available (team size, budget, infrastructure)?
- Risk tolerance: Is this production-critical or experimental?
- Reversibility: Must this decision be reversible?
```

### 2. Quantify When Possible

**Good:**
```
**Timeline:**
- Option 1: 2-3 hours
- Option 2: 1-2 days
- Option 3: 1 week
```

**Poor:**
```
**Timeline:**
- Option 1: Quick
- Option 2: A while
- Option 3: Longer
```

### 3. Be Honest About Unknowns

```
**Option 2: Microservices Architecture**

⚠️ **Unknown:** Migration effort could be 2-4 weeks depending on current coupling.
Would need to audit codebase to give accurate estimate.
```

### 4. Provide "Escape Hatch"

Always include:
```
**Not satisfied with these options?**

I can also:
- Research more alternatives
- Combine aspects of multiple options
- Deep-dive on any specific approach
- Prototype a solution to test viability
```


## Red Flags - Don't Do This

| Action | Why It's Wrong |
|--------|----------------|
| Only present one "option" | That's not a choice |
| Present 8+ options | Decision paralysis |
| Hide significant cons | User can't make informed choice |
| Recommend without reasoning | User can't evaluate recommendation |
| Ignore stated constraints | Wasting user's time |
| Present obviously bad options as viable | Undermines trust |


## Quick Reference

| User Request | Action |
|--------------|--------|
| "fix or provide options" | Assess if fix obvious → If yes: present fix, if no: present options |
| "what are my options" | Understand context → Generate 2-4 options → Present with trade-offs |
| "help me decide" | Clarify decision factors → Compare approaches → Recommend with reasoning |
| "show alternatives" | Generate alternatives → Analyze pros/cons → Present structured comparison |


## The Bottom Line

```
Decision support → Clear options + Honest trade-offs + Reasoned recommendation
Otherwise → Confusion + Poor decisions + Regret
```

**Understand context. Present real choices. Support with reasoning. Respect their decision.**
