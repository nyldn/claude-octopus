---
command: plan
description: "Intelligent plan builder - creates strategic execution plans (doesn't execute). Use /octo:embrace to execute plans."
aliases:
  - build-plan
  - intent
---

# Plan - Intelligent Plan Builder

**Creates strategic execution plans based on user intent. Saves plans for review and optional execution with /octo:embrace.**

## Key Behavior

- **Creates plans** - Captures intent, analyzes requirements, generates weighted execution strategy
- **Saves to files** - Stores plan (`.claude/session-plan.md`) and intent contract (`.claude/session-intent.md`)
- **Doesn't execute** - Plans are saved for review; execution requires user confirmation
- **Optional execution** - Can invoke `/octo:embrace` immediately or user can execute later

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:plan <arguments>`):

### Step 1: Capture Comprehensive Intent

**CRITICAL: Start by capturing the user's full intent using structured questions.**

Ask 5 comprehensive questions to understand what they're trying to accomplish:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What are you ultimately trying to accomplish?",
      header: "Goal",
      multiSelect: false,
      options: [
        {label: "Research a topic", description: "Gather information and options"},
        {label: "Make a decision", description: "Choose between alternatives"},
        {label: "Build something", description: "Create implementation or artifact"},
        {label: "Review/improve existing", description: "Assess and enhance what's there"},
        {label: "I'll describe it", description: "Let me write my own goal"}
      ]
    },
    {
      question: "How much do you already know about this?",
      header: "Knowledge",
      multiSelect: false,
      options: [
        {label: "Just starting", description: "Need to learn the landscape"},
        {label: "Some familiarity", description: "Know basics, need deeper dive"},
        {label: "Well-informed", description: "Know options, need execution"},
        {label: "Expert", description: "Just need implementation/validation"}
      ]
    },
    {
      question: "How clear is the scope?",
      header: "Clarity",
      multiSelect: false,
      options: [
        {label: "Vague idea", description: "Not sure exactly what I need"},
        {label: "General direction", description: "Know the area, need specifics"},
        {label: "Clear requirements", description: "Know what to build"},
        {label: "Fully specified", description: "Have detailed specifications"}
      ]
    },
    {
      question: "What defines success for you?",
      header: "Success",
      multiSelect: true,
      options: [
        {label: "Clear understanding", description: "I know what to do next"},
        {label: "Team alignment", description: "Everyone agrees on approach"},
        {label: "Working solution", description: "Implementation that functions"},
        {label: "Production-ready", description: "Fully tested and validated"}
      ]
    },
    {
      question: "What are your key constraints?",
      header: "Constraints",
      multiSelect: true,
      options: [
        {label: "Time pressure", description: "Need results quickly"},
        {label: "Must fit architecture", description: "Constrained by existing systems"},
        {label: "Team skill set", description: "Limited by team capabilities"},
        {label: "High stakes", description: "Significant risk if wrong"}
      ]
    }
  ]
})
```

**If user selected "I'll describe it" for goal, follow up with:**
```
Can you describe in 1-2 sentences what you're trying to accomplish?
```

### Step 2: Create Intent Contract

**Use the skill-intent-contract system to capture this formally:**

1. Create `.claude/session-intent.md` with:
   - Job statement (what user is trying to accomplish)
   - Success criteria (from their answers)
   - Boundaries (derived from constraints)
   - Context (knowledge level, clarity, constraints)

2. Store answers from the 5 questions in the contract

### Step 3: Analyze and Route (v7.24.0+: Hybrid Planning)

**NEW in v7.24.0:** Intelligent routing between native plan mode and octopus workflows.

#### Native Plan Mode Detection

First, check if native `EnterPlanMode` would be beneficial:

```javascript
// Conditions that favor native plan mode
const nativePlanModePreferred = (
  goal === "Build something" &&
  scope_clarity === "Clear requirements" &&
  knowledge_level === "Well-informed" &&
  !requires_multi_ai &&  // Simple single-phase planning
  !success.includes("Team alignment")  // No multi-perspective needs
)

if (nativePlanModePreferred) {
  // Suggest native plan mode
  AskUserQuestion({
    questions: [{
      question: "Would you like to use native plan mode or multi-AI orchestration?",
      header: "Planning Mode",
      multiSelect: false,
      options: [
        {
          label: "Native plan mode (Recommended)",
          description: "Fast, single-phase planning with Claude. Good for straightforward implementation plans."
        },
        {
          label: "Multi-AI orchestration",
          description: "Research with Codex + Gemini + Claude. Better for complex problems requiring diverse perspectives."
        }
      ]
    }]
  })
}
```

**When to use native EnterPlanMode:**
- ✅ Single-phase planning (just need a plan, no execution)
- ✅ Well-defined requirements
- ✅ Quick architectural decisions
- ✅ When context clearing after planning is OK

**When to use /octo:plan (octopus workflows):**
- ✅ Multi-AI orchestration (Codex + Gemini + Claude)
- ✅ Double Diamond 4-phase execution
- ✅ State needs to persist across sessions
- ✅ Complex intent capture with routing
- ✅ High-stakes decisions requiring multiple perspectives

#### Routing Logic (Octopus Workflows)

```
IF knowledge_level == "Just starting":
  DISCOVER_WEIGHT += 20%

IF scope_clarity == "Vague idea":
  DEFINE_WEIGHT += 15%
  DISCOVER_WEIGHT += 10%

IF scope_clarity == "Fully specified":
  DEVELOP_WEIGHT += 15%
  DELIVER_WEIGHT += 10%

IF "Working solution" OR "Production-ready" in success:
  DEVELOP_WEIGHT += 15%
  DELIVER_WEIGHT += 10%

IF "High stakes" in constraints:
  DELIVER_WEIGHT += 15%  (more validation)
  requires_multi_ai = true  (multiple perspectives needed)

IF goal == "Research a topic":
  ROUTE_TO: discover (weighted heavy)
  requires_multi_ai = true

IF goal == "Make a decision":
  ROUTE_TO: debate OR (discover + define)
  requires_multi_ai = true

IF goal == "Build something":
  IF scope_clarity in ["Clear requirements", "Fully specified"] AND NOT requires_multi_ai:
    SUGGEST: native plan mode
  ELSE:
    ROUTE_TO: embrace (all 4 phases, weighted)

IF goal == "Review/improve existing":
  ROUTE_TO: review OR deliver
```

#### Default Phase Weights

Start with 25% each, adjust based on signals:
- Discover: 25% ± 20% (research & exploration)
- Define: 25% ± 15% (scope & boundaries)
- Develop: 25% ± 15% (implementation)
- Deliver: 25% ± 15% (validation & review)

### Step 4: Present the Plan

**Display a comprehensive plan visualization:**

```
🐙 **CLAUDE OCTOPUS PLAN**

WHAT YOU'LL END UP WITH:
[Clear description of the deliverable based on their goal]

HOW WE'LL GET THERE:

DISCOVER ████████████████ 40%
Research the landscape — Gather evidence and options
→ /octo:discover (extended depth)

DEFINE ████ 15%
Lock the scope — Confirm boundaries and approach
→ /octo:define (light touch)

DEVELOP ████████████ 30%
Build the solution — Create the implementation
→ /octo:develop

DELIVER ██████ 15%
Validate quality — Review and refine
→ /octo:deliver

Provider Availability:
🔴 Codex CLI: [Available ✓ / Not installed ✗]
🟡 Gemini CLI: [Available ✓ / Not installed ✗]
🔵 Claude: Available ✓

YOUR INVOLVEMENT: [Checkpoints / Semi-autonomous / Hands-off]

Time estimate: [Rough estimate based on scope]
```

### Step 5: Save the Plan

**CRITICAL: The plan command creates plans, it does NOT execute them by default.**

1. **Save plan to `.claude/session-plan.md`:**

```markdown
# Session Plan

**Created:** [timestamp]
**Intent Contract:** See .claude/session-intent.md

## What You'll End Up With
[Clear description of deliverable]

## How We'll Get There

### Phase Weights
- Discover: [X]% - [Brief description]
- Define: [X]% - [Brief description]
- Develop: [X]% - [Brief description]
- Deliver: [X]% - [Brief description]

### Execution Commands
To execute this plan, run:
\`\`\`bash
/octo:embrace "[user's goal]"
\`\`\`

Or execute phases individually:
- `/octo:discover` (if Discover > 20%)
- `/octo:define` (if Define > 20%)
- `/octo:develop` (if Develop > 20%)
- `/octo:deliver` (if Deliver > 20%)

## Provider Requirements
🔴 Codex CLI: [Available ✓ / Not installed ✗]
🟡 Gemini CLI: [Available ✓ / Not installed ✗]
🔵 Claude: Available ✓

## Success Criteria
[From intent contract]

## Next Steps
1. Review this plan
2. Adjust if needed (re-run /octo:plan)
3. Execute with /octo:embrace when ready
```

2. **Display the plan to the user** (same visualization as before)

3. **Show completion message:**

```
✅ Plan saved to .claude/session-plan.md

To execute this plan, run:
  /octo:embrace "[user's goal]"

Or adjust the plan:
  /octo:plan  (re-run to modify)
```

### Step 6: Offer Next Actions (Optional Execution)

**Ask user what they want to do with the plan:**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What would you like to do with this plan?",
      header: "Next Action",
      multiSelect: false,
      options: [
        {label: "Review and execute later", description: "Plan saved, I'll run /octo:embrace when ready (Recommended)"},
        {label: "Adjust plan weights", description: "Change phase emphasis before saving"},
        {label: "Execute now", description: "Run /octo:embrace immediately with this plan"},
        {label: "Different approach", description: "Suggest an alternative strategy"}
      ]
    }
  ]
})
```

**If "Review and execute later":**
- Save plan and exit
- User can review `.claude/session-plan.md` at their leisure
- User runs `/octo:embrace` when ready

**If "Adjust plan weights":**
- Ask which phases to emphasize/de-emphasize
- Regenerate plan visualization
- Save updated plan
- Return to Step 6 (ask again what to do)

**If "Execute now":**
- Invoke `/octo:embrace` skill with the user's goal
- Pass the intent contract and phase weights
- Let embrace workflow handle execution

**If "Different approach":**
- Ask what they'd prefer
- Regenerate from Step 3
- Return to Step 6 (ask again what to do)

### Step 7: Integration with /octo:embrace (Optional Execution)

**If user chose "Execute now" in Step 6:**

The plan command should invoke the `/octo:embrace` skill, which handles:
- Execution of all 4 phases (Discover → Define → Develop → Deliver)
- Using the phase weights from the plan
- Referencing the intent contract
- Validation against success criteria
- Final reporting

**Important:** The plan command itself does NOT execute workflows. It delegates to `/octo:embrace` for execution.

### Step 8: Plan Command Completes

**The plan command exits after:**
- Creating and saving the plan (`.claude/session-plan.md`)
- Creating the intent contract (`.claude/session-intent.md`)
- Optionally invoking `/octo:embrace` if user requested immediate execution

**The plan command does NOT:**
- Execute workflows directly (delegates to `/octo:embrace`)
- Validate results (that's `/octo:embrace`'s responsibility)
- Implement anything (that's what workflows do)

**Clear separation of concerns:**
- `/octo:plan` → Creates strategic plans
- `/octo:embrace` → Executes plans through 4-phase workflow
- Individual phase commands → Execute specific phases

---

## Usage Examples

### Example 1: Research Mode

```
User: /octo:plan

[After 5 questions show research need]

Claude presents plan:
DISCOVER ████████████████████ 50%
DEFINE ██████ 15%
DEVELOP ████ 10%
DELIVER ██████████ 25%

"You'll get: Comprehensive research report with recommendations"

✅ Plan saved to .claude/session-plan.md

To execute this plan, run:
  /octo:embrace "research topic X"

[Asks: "What would you like to do with this plan?"]
User selects: "Review and execute later"

→ Plan saved, user reviews it, runs /octo:embrace when ready
```

### Example 2: Build Mode with Immediate Execution

```
User: /octo:plan

[After 5 questions show build need with clear requirements]

Claude presents plan:
DISCOVER ████ 10%
DEFINE ██████ 15%
DEVELOP ████████████████ 40%
DELIVER ██████████████ 35%

"You'll get: Working implementation with tests"

[Asks: "What would you like to do with this plan?"]
User selects: "Execute now"

→ Invokes /octo:embrace immediately
→ Execution begins with saved plan and intent contract
```

### Example 3: Decision Mode

```
User: /octo:plan "Should we use Redis or PostgreSQL?"

[After 5 questions show decision need]

Claude presents plan:
→ Recommends /octo:debate for this type of decision

Plan saved with recommendation to use debate workflow

[Asks: "What would you like to do with this plan?"]
User selects: "Execute now"

→ Invokes /octo:debate instead of /octo:embrace
```

---

## Workflow Routing Table

| User Goal | Knowledge | Clarity | → Route To |
|-----------|-----------|---------|------------|
| Research | Just starting | Vague | discover (heavy) |
| Research | Some familiarity | General | discover (moderate) → define |
| Decision | Well-informed | Clear | debate |
| Build | Expert | Fully specified | develop → deliver |
| Build | Some familiarity | General | embrace (all phases) |
| Review | Well-informed | Clear | review OR deliver |

---

## Integration with Intent Contract

The plan command is the primary entry point for creating intent contracts. It:

1. Captures comprehensive user intent
2. Creates `.claude/session-intent.md`
3. Routes to appropriate workflows
4. Passes intent contract through execution
5. Validates outputs against original intent

This closes the loop between user intention and delivered results.

---

## Benefits

**For Users:**
- **Creates strategic plans** without automatic execution
- **Review before committing** - see the plan, adjust if needed
- **Execute when ready** - run `/octo:embrace` at your own pace
- **Intent contract** - captures goals and validates against them
- **Customized approach** - phase weights adapt to your situation
- **Clear separation** - planning vs. execution are distinct steps

**For Complex Tasks:**
- **Intelligent routing** - recommends best workflow based on context
- **Phase weighting** - optimizes effort distribution
- **Intent contract** - ensures alignment throughout execution
- **Flexible execution** - save plan, review, adjust, then execute

**Workflow Separation:**
- `/octo:plan` → Strategic planning (creates plans, doesn't execute)
- `/octo:embrace` → Execution (runs the full 4-phase workflow)
- Individual phases → Execute specific phases independently

---

**Ready to use!** Users can invoke with `/octo:plan` to create customized execution plans, then execute with `/octo:embrace` when ready.
