---
name: skill-intent-contract
disable-model-invocation: true
description: "Use when starting a complex or ambiguous task that risks scope drift"
---

# Intent Contract System

## Purpose

The intent contract creates a **persistent record of user intent** that:
- Captures what the user is trying to accomplish
- Defines success criteria upfront
- Establishes boundaries and constraints
- Travels through the entire workflow
- Validates final outputs against original intent

This closes the loop between intention and delivery.

---

## Intent Contract Structure

The intent contract is stored in the current resolved plan run directory as `session-intent.md`. Use `scripts/plan-storage.sh` to create or recover that directory; never write a loose intent file into `.claude/`.

```markdown
# Intent Contract

**Created**: [ISO timestamp]
**Workflow**: [discover/embrace/review/etc.]
**Status**: [active/validating/completed]

## Job Statement
What the user is trying to accomplish (JTBD framework).

[User's goal in plain language]

## Success Criteria

### Good Enough
- [Minimum viable success criterion 1]
- [Minimum viable success criterion 2]

### Exceptional
- [Excellence criterion 1]
- [Excellence criterion 2]

## Boundaries
What this should NOT be:
- [Boundary 1: What to avoid]
- [Boundary 2: What's out of scope]

## Context & Constraints

**Stakeholders**: [Who needs this to work for them]
**Existing Assets**: [What to build on]
**Timeline**: [Time constraints if any]
**Technical Constraints**: [Platform, language, dependencies]

## Clarifying Context
[Any answers from the 3-question pattern]

## Task Allocation
**Risk**: [low | intermediate | high]
**Initiative**: [human | AI | shared] — who starts and proposes
**Control**: [human | AI | shared] — who oversees execution as it runs
**Decision rights**: [human | AI] — who has final say on the outcome
**AI role**: [none | executor | collaborator | challenger]
**Execution disposition**: [AI-assisted | human-only | pending-user-decision]
**Escalation decision**: [not-needed | pending | user's recorded resolution]
**Resolved AUTONOMY_MODE**: [supervised | semi-autonomous | loop-until-approved | autonomous | not-applicable (contract-only sentinel)]

## Validation Checklist
- [ ] Meets "good enough" criteria
- [ ] Respects all boundaries
- [ ] Works for all stakeholders
- [ ] Builds on existing assets appropriately
- [ ] Allocation still fits what the task turned out to be
```

---

## Implementation Instructions

### When to Create Intent Contract

Create an intent contract when:
- User invokes a major workflow (`/octo:embrace`, `/octo:discover`, `/octo:plan`)
- User explicitly asks to "plan" or "set goals" for a task
- A workflow requires multiple phases and validation

**Do NOT create for:**
- Quick, single-action commands
- Simple file reads or searches
- Conversational questions

### Step 0: Allocate the work before scoping it

Run this before capturing intent. The question is not how to run the task across
agents but whether it should be delegated at all, and if so, which parts of the
authority go where. Framework: Afroogh, Varshney & D'Cruz (2025), *A Task-Driven
Human-AI Collaboration* ([arXiv:2505.18422](https://arxiv.org/abs/2505.18422)).

**Classify risk.** Complexity is already scored elsewhere — defer to
`estimate_complexity` and `classify_cynefin` in `scripts/lib/routing.sh` rather
than re-deriving it. Risk is a separate axis that nothing in the codebase
measures, so judge it here on three questions:

- **Irreversibility** — can the effect be undone, and at what cost?
- **Consequence** — is anything material at stake: safety, money, data, users?
- **Accountability** — is a specific person expected to answer for the outcome?

| Risk | Reading |
|------|---------|
| **Low** | Reversible, no material consequence, no named accountability. |
| **Intermediate** | Reversible only at real cost, or consequence is unclear. |
| **High** | Irreversible, materially consequential, or someone must answer for it. |

**Allocate the three dimensions separately.** They are independent, and treating
them as one axis is the mistake this step exists to prevent. People readily hand
AI the *initiative* on unfamiliar work while keeping control and decision rights
— an allocation a single autonomy slider cannot express.

- **Initiative** — who starts, proposes, drafts.
- **Control** — who oversees execution while it runs.
- **Decision rights** — who has final say on the result.

Record every outcome explicitly:

| Risk / complexity | Initiative | Control | Decision rights | AI role | Execution disposition | Escalation decision | Mode |
|---|---|---|---|---|---|---|---|
| Low / low | AI | AI | AI | executor | AI-assisted | not-needed | `autonomous` |
| Low / high | shared | human | human | collaborator | AI-assisted | not-needed | `loop-until-approved` |
| High / low | human | human | human | executor | AI-assisted | not-needed | `supervised` |
| High / high | human | human | human | challenger | AI-assisted | not-needed | `supervised` |

The High / high allocation is adversarial: the human leads while AI attacks the
proposed decision as a deliberate counterweight to the human's own bias. In High /
low work, AI may execute only the bounded actions the human directly approves.

**The rule that inverts.** For **intermediate-risk** work where uncertainty is
highest, the cited evidence says avoid AI entirely — "neither as a gatekeeper nor
as a second opinion". This contradicts the smooth intuition that middling risk
implies middling involvement, and it also sits in tension with the same paper's
broader claim that complete human autonomy is rarely justified. That tension is
real and unresolved; surface it to the user and let them decide rather than
quietly picking a side.

**Resolve to a setting.** The workflow engine reads one variable,
`AUTONOMY_MODE`, with four values:

| Allocation | `AUTONOMY_MODE` |
|---|---|
| Human holds control and decision rights, approving each phase | `supervised` |
| AI runs; human is pulled in on failures and quality gates | `semi-autonomous` |
| AI runs and iterates; human holds final decision rights | `loop-until-approved` |
| AI holds all three | `autonomous` |

Record the three dimensions *and* the resolved mode. The mapping is lossy: one
axis cannot represent three independent allocations, so a contract that stores
only the mode loses the reason it was chosen. That record is what a later
reviewer needs when the allocation turns out to have been wrong.

`not-applicable` is a persisted, contract-only sentinel for human-only work; it
is not a fifth runtime value and must not be passed to the workflow engine.

For intermediate risk, record `Execution disposition: pending-user-decision`.
Record `Escalation decision: pending`, then stop before execution.
Ask the user to choose human-only handling or a specific documented AI allocation.
Record their answer, rewrite the Task Allocation fields to match it, and change
`Escalation decision` to the user's resolution before continuing. For a human-only
resolution, record `AI role: none` and `Resolved AUTONOMY_MODE: not-applicable`;
human-only `not-applicable` must not be passed to the workflow engine. Resolve to the
supported human-only behavior and do not execute AI work in that state.

For a documented AI-assisted resolution, record every Task Allocation field:

- `Initiative`, `Control`, `Decision rights`, and `AI role` from the chosen allocation
- `Execution disposition: AI-assisted`
- `Escalation decision: user's recorded resolution`
- `Resolved AUTONOMY_MODE`: exactly one of `supervised`, `semi-autonomous`,
  `loop-until-approved`, or `autonomous`, mapped using the table above

Validate the selected runtime mode and only then execute. The runtime must reject
`not-applicable` and every unknown or unsupported mode before workflow execution rather
than defaulting to autonomous behavior.

### Step 1: Capture Intent

After asking the 3 clarifying questions in a workflow, prompt the user to define:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What are you ultimately trying to accomplish?",
      header: "Goal",
      multiSelect: false,
      options: [
        {label: "Let me describe it", description: "I'll write my own goal statement"},
        {label: "Make a decision", description: "Choose between options"},
        {label: "Create deliverable", description: "Build something specific"},
        {label: "Understand a problem", description: "Research and learn"}
      ]
    },
    {
      question: "What defines success for this?",
      header: "Success",
      multiSelect: true,
      options: [
        {label: "Clear recommendation", description: "Know what to do next"},
        {label: "Working implementation", description: "Code that functions"},
        {label: "Team alignment", description: "Everyone understands"},
        {label: "Problem solved", description: "Issue is resolved"}
      ]
    },
    {
      question: "What should this NOT be or do?",
      header: "Boundaries",
      multiSelect: true,
      options: [
        {label: "Over-engineered", description: "Keep it simple"},
        {label: "Incomplete", description: "Must be production-ready"},
        {label: "Disconnected", description: "Must fit our architecture"},
        {label: "Risky", description: "Avoid experimental approaches"}
      ]
    }
  ]
})
```

If user selects "Let me describe it", follow up with a text prompt for their custom goal.

### Step 2: Write Intent Contract File

Resolve a unique run directory, then use the Write tool to create its `session-intent.md`:

```bash
PLAN_STORAGE="${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}/scripts/plan-storage.sh"
OCTO_PLAN_DIR="$("$PLAN_STORAGE" current "$PWD" 2>/dev/null || "$PLAN_STORAGE" create "$PWD")"
cat > "${OCTO_PLAN_DIR}/session-intent.md" <<EOF
# Intent Contract

**Created**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Workflow**: ${WORKFLOW_NAME}
**Status**: active

## Job Statement
${USER_GOAL}

## Success Criteria

### Good Enough
${MIN_SUCCESS_CRITERIA}

### Exceptional
${EXCEPTIONAL_CRITERIA}

## Boundaries
What this should NOT be:
${BOUNDARIES}

## Context & Constraints

**Stakeholders**: ${STAKEHOLDERS}
**Timeline**: ${TIMELINE}

## Clarifying Context
${THREE_QUESTION_ANSWERS}

## Validation Checklist
- [ ] Meets "good enough" criteria
- [ ] Respects all boundaries
- [ ] Works for all stakeholders
EOF
```

### Step 3: Reference During Execution

Throughout the workflow, recover the current plan directory with `plan-storage.sh current "$PWD"` and periodically read its `session-intent.md` to:
- Stay aligned with user goals
- Make decisions consistent with boundaries
- Keep stakeholders in mind

At key decision points, explicitly say:
```
Checking against intent contract: [reference specific criterion]
```

### Step 4: Validate at End

When the workflow completes, read the resolved plan directory's `session-intent.md` and validate:

**Validation Process:**

1. **Read the intent contract**
2. **Check each success criterion:**
   - ✓ Met - explain how
   - ✗ Not met - explain why and what's needed
   - ~ Partially met - explain gaps

3. **Check boundaries:**
   - ✓ Respected - confirm
   - ✗ Violated - explain what happened

4. **Generate validation report:**

```markdown
# Validation Report

## Success Criteria Check

### Good Enough Criteria
- [✓] Criterion 1: [How it was met]
- [✗] Criterion 2: [Why not met, what's needed]

### Exceptional Criteria
- [~] Criterion 1: [Partial progress explanation]

## Boundary Check
All boundaries respected: [Yes/No]
- Boundary 1: [✓/✗] [Explanation]

## Gaps & Next Steps
[If any criteria not met, list concrete next steps]

## Overall Assessment
[Summary: Does this fulfill the original intent?]
```

5. **Present to user:**
   - Show the validation report
   - Ask if they want to address any gaps
   - Update intent contract status to "completed" or "validating"

### Step 5: Update Intent Contract Status

Update the `Status` field in the resolved plan directory's `session-intent.md`:
- `active` → workflow in progress
- `validating` → checking against criteria
- `completed` → all criteria met, boundaries respected
- `incomplete` → some criteria not met, gaps identified

---

## Integration with Workflows

### Embrace Workflow

```
1. Ask 3 clarifying questions (scope, focus, autonomy)
2. Create intent contract
3. DISCOVER phase (reference intent)
4. DEFINE phase (reference intent)
5. DEVELOP phase (reference intent)
6. DELIVER phase (reference intent)
7. Validate against intent contract
8. Present validation report
```

### Discover Workflow

```
1. Ask 3 clarifying questions (depth, focus, output)
2. Create intent contract
3. Execute multi-provider research
4. Synthesize findings
5. Validate against intent contract
6. Present validation report
```

### Plan Workflow (Future)

```
1. Capture comprehensive intent
2. Create intent contract
3. Route to appropriate workflows
4. Execute custom sequence
5. Validate against intent contract
6. Present validation report
```

---

## Example Intent Contract

```markdown
# Intent Contract

**Created**: 2026-01-21T15:30:00Z
**Workflow**: embrace
**Status**: active

## Job Statement
Build a user authentication system that our team can implement and maintain.

## Success Criteria

### Good Enough
- Team understands what to build
- Clear technical approach selected
- Security considerations documented
- Implementation plan with steps

### Exceptional
- Multiple authentication methods evaluated
- Security audit performed
- Code examples provided
- Integration tests included

## Boundaries
What this should NOT be:
- Over-engineered with unnecessary features
- Disconnected from our existing Node.js/Express stack
- Experimental or unproven technologies

## Context & Constraints

**Stakeholders**: Development team (5 engineers), Product manager
**Existing Assets**: Express.js API, PostgreSQL database
**Timeline**: Need to start implementation next sprint
**Technical Constraints**: Must work with Express.js, PostgreSQL

## Clarifying Context

**Scope**: Medium feature (multiple components)
**Focus Areas**: Security, Architecture design
**Autonomy**: Supervised (review after each phase)

## Validation Checklist
- [ ] Meets "good enough" criteria
- [ ] Respects all boundaries
- [ ] Works for all stakeholders
- [ ] Builds on existing assets appropriately
```

---

## Benefits

**For Users:**
- Clear expectations set upfront
- No forgotten requirements
- Validation against original goals
- Closed-loop accountability

**For Workflows:**
- Clear success criteria to optimize for
- Boundaries to constrain solutions
- Context for better decisions
- Validation framework built-in

---

**Ready to use!** Workflows can now create and validate against persistent intent contracts.
