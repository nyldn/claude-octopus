---
name: skill-intent-contract
description: |
  Persistent intent contract system that captures user goals, success criteria,
  and constraints at the start of workflows and validates outputs against them.

  Automatically invoked by workflows to create closed-loop accountability.
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

The intent contract is stored in `.claude/session-intent.md` and follows this format:

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

## Validation Checklist
- [ ] Meets "good enough" criteria
- [ ] Respects all boundaries
- [ ] Works for all stakeholders
- [ ] Builds on existing assets appropriately
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

Use the Write tool to create `.claude/session-intent.md`:

```bash
cat > .claude/session-intent.md <<EOF
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

Throughout the workflow, periodically read `.claude/session-intent.md` to:
- Stay aligned with user goals
- Make decisions consistent with boundaries
- Keep stakeholders in mind

At key decision points, explicitly say:
```
Checking against intent contract: [reference specific criterion]
```

### Step 4: Validate at End

When the workflow completes, read `.claude/session-intent.md` and validate:

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

Update the `Status` field in `.claude/session-intent.md`:
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
