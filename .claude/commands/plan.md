---
command: plan
description: "Intelligent plan builder - captures intent and routes to optimal workflow sequence"
aliases:
  - build-plan
  - intent
---

# Plan - Intelligent Plan Builder

**Creates custom workflow sequences based on user intent with routing intelligence.**

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

### Step 5: Confirm Execution

**Ask user to confirm before proceeding:**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Does this plan look good?",
      header: "Proceed",
      multiSelect: false,
      options: [
        {label: "Yes, execute it", description: "Run the plan as shown"},
        {label: "Adjust weights", description: "I want to change phase emphasis"},
        {label: "Different approach", description: "Suggest an alternative"},
        {label: "Let me think", description: "Just show me the plan for now"}
      ]
    }
  ]
})
```

**If "Adjust weights":** Let user specify which phases to emphasize/de-emphasize
**If "Different approach":** Ask what they'd prefer and regenerate
**If "Let me think":** Save plan to `.claude/session-plan.md` and exit

### Step 6: Execute the Plan

**Run the weighted workflow sequence:**

1. **Check provider availability** (codex, gemini CLIs)

2. **Execute each phase with appropriate depth:**
   - <20% weight: Light touch, quick pass
   - 20-30% weight: Standard depth
   - 30-40% weight: Extended exploration
   - >40% weight: Deep dive, comprehensive

3. **Pass intent contract through all phases** so they stay aligned

4. **At checkpoints** (if user wants involvement):
   - Show progress
   - Validate against intent contract
   - Ask if adjustments needed

5. **Reference the intent contract** at key decision points

### Step 7: Validate Against Intent Contract

**When execution completes:**

1. Read `.claude/session-intent.md`
2. Check each success criterion:
   - ✓ Met — explain how
   - ✗ Not met — explain why, what's needed
   - ~ Partially met — explain gaps

3. Check boundaries (constraints respected?)

4. Generate validation report:

```markdown
# Validation Report

## Success Criteria Check
### Minimum Viable Success
- [✓] Criterion 1: [How it was met]
- [✗] Criterion 2: [Why not met, what's needed]

### Excellence Criteria
- [~] Criterion 1: [Partial progress]

## Boundary Check
- [✓] Constraint 1 respected
- [✓] Constraint 2 respected

## Gaps & Next Steps
[If any criteria not met, list concrete next steps]

## Overall Assessment
[Does this fulfill the original intent? Yes/No + summary]
```

5. Present validation report to user
6. Ask if they want to address gaps
7. Update intent contract status

### Step 8: Offer Next Actions

**After validation:**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What would you like to do next?",
      header: "Next",
      multiSelect: false,
      options: [
        {label: "Address gaps", description: "Fix criteria that weren't met"},
        {label: "Export results", description: "Save to document (PPTX/PDF/DOCX)"},
        {label: "Start implementation", description: "Move to code"},
        {label: "Done", description: "This completes my goal"}
      ]
    }
  ]
})
```

---

## Usage Examples

### Example 1: Research Mode

```
User: /octo:plan

[After 5 questions show research need]

Claude presents:
DISCOVER ████████████████████ 50%
DEFINE ██████ 15%
DEVELOP ████ 10%
DELIVER ██████████ 25%

"You'll get: Comprehensive research report with recommendations"
→ Routes to heavy discover, light define, validation
```

### Example 2: Build Mode

```
User: /octo:plan

[After 5 questions show build need with clear requirements]

Claude presents:
DISCOVER ████ 10%
DEFINE ██████ 15%
DEVELOP ████████████████ 40%
DELIVER ██████████████ 35%

"You'll get: Working implementation with tests"
→ Routes to light discover, heavy develop/deliver
```

### Example 3: Decision Mode

```
User: /octo:plan "Should we use Redis or PostgreSQL?"

[After 5 questions show decision need]

Claude presents:
→ Routes to /octo:debate (special case)

"You'll get: Multi-AI debate with recommendation"
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
- Don't need to know which command to use
- Clear plan before execution starts
- Customized approach based on their situation
- Validation against original goals

**For Complex Tasks:**
- Intelligent routing based on context
- Phase weighting optimizes for user needs
- Intent contract ensures alignment
- Validation prevents missed requirements

---

**Ready to use!** Users can invoke with `/octo:plan` and get intelligently routed workflows.
