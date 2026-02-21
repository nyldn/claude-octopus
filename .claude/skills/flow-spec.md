---
name: flow-spec
aliases:
  - spec
  - nlspec
  - specification
description: NLSpec authoring — structured specification from multi-AI research
execution_mode: enforced
validation_gates:
  - orchestrate_sh_executed
  - synthesis_file_exists
  - nlspec_completeness_validated
---

# STOP - SKILL ALREADY LOADED

**DO NOT call Skill() again. DO NOT load any more skills. Execute directly.**

---

## EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

This skill uses **ENFORCED execution mode**. You MUST follow this exact 8-step sequence.

---

### STEP 1: Clarifying Questions (MANDATORY)

**Ask via AskUserQuestion BEFORE any other action.**

You MUST gather these inputs from the user:

```
AskUserQuestion with these questions:

1. **What to specify**: Project or feature name + brief description
   - "What system/feature should I specify?"

2. **Actors**: Who interacts with this system?
   - Options: End Users, Developers, Admins, External Services, Other

3. **Key constraints**: What matters most?
   - Options: Performance, Security, Compatibility, Scale
   - (multiSelect: true)

4. **Complexity class**: How complex is this?
   - Clear (well-understood, straightforward)
   - Complicated (multiple parts, but knowable)
   - Complex (emergent behavior, unknowns)
```

If user provided a description inline with the command (e.g., `/octo:spec user authentication system`), use that as the project description but STILL ask remaining questions (actors, constraints, complexity).

If user says "skip" for any question, note assumptions and proceed.

**DO NOT PROCEED TO STEP 2 until questions answered.**

---

### STEP 2: Display Visual Indicators (MANDATORY - BLOCKING)

**Check provider availability:**

```bash
command -v codex &> /dev/null && codex_status="Available" || codex_status="Not installed"
command -v gemini &> /dev/null && gemini_status="Available" || gemini_status="Not installed"
```

**Display this banner BEFORE orchestrate.sh execution:**

```
CLAUDE OCTOPUS ACTIVATED - NLSpec Authoring Mode
Spec Phase: Generating structured specification for [project name]

Provider Availability:
Codex CLI: ${codex_status}
Gemini CLI: ${gemini_status}
Claude: Available (Synthesis & NLSpec generation)

Estimated Cost: $0.01-0.05
Estimated Time: 3-7 minutes
```

**Validation:**
- If BOTH Codex and Gemini unavailable -> STOP, suggest: `/octo:setup`
- If ONE unavailable -> Continue with available provider(s)
- If BOTH available -> Proceed normally

**DO NOT PROCEED TO STEP 3 until banner displayed.**

---

### STEP 3: Read Prior State (MANDATORY - State Management)

**Before executing the workflow, read any prior context:**

```bash
# Initialize state if needed
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state

# Set current workflow
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" set_current_workflow "flow-spec" "spec"

# Get prior decisions (if any)
prior_decisions=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_decisions "all")

# Get context from previous phases (e.g., discover)
prior_context=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" read_state | jq -r '.context')

# Display what you found (if any)
if [[ "$prior_decisions" != "[]" && "$prior_decisions" != "null" ]]; then
  echo "Building on prior decisions:"
  echo "$prior_decisions" | jq -r '.[] | "  - \(.decision) (\(.phase)): \(.rationale)"'
fi
```

**This provides context from:**
- Prior discover phases (if user ran `/octo:discover` first)
- Architectural decisions already made
- User vision captured in earlier phases

**DO NOT PROCEED TO STEP 4 until state read.**

---

### STEP 4: Execute orchestrate.sh probe (MANDATORY - Use Bash Tool)

**You MUST execute this command via the Bash tool:**

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh probe "specification research for: <project description>. Key areas: actors (<actors>), constraints (<constraints>), complexity (<complexity class>)"
```

Incorporate the user's answers from Step 1 into the probe query to focus the research.

**CRITICAL: You are PROHIBITED from:**
- Researching directly without calling orchestrate.sh
- Using web search instead of orchestrate.sh
- Claiming you're "simulating" the workflow
- Proceeding to Step 5 without running this command
- Substituting with direct Claude analysis

**This is NOT optional. You MUST use the Bash tool to invoke orchestrate.sh.**

---

### STEP 5: Verify Probe Synthesis (MANDATORY - Validation Gate)

**After orchestrate.sh completes, verify it succeeded:**

```bash
# Find the latest synthesis file (created within last 10 minutes)
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "probe-synthesis-*.md" -mmin -10 2>/dev/null | head -n1)

if [[ -z "$SYNTHESIS_FILE" ]]; then
  echo "VALIDATION FAILED: No synthesis file found"
  echo "orchestrate.sh did not execute properly"
  exit 1
fi

echo "VALIDATION PASSED: $SYNTHESIS_FILE"
cat "$SYNTHESIS_FILE"
```

**If validation fails:**
1. Report error to user
2. Show logs from `~/.claude-octopus/logs/`
3. DO NOT proceed with generating NLSpec
4. DO NOT substitute with direct research

---

### STEP 6: Synthesize into NLSpec Format (MANDATORY)

**Read the probe synthesis file from Step 5 and the user's answers from Step 1.**

Synthesize into the NLSpec template below. This is YOUR (Claude's) synthesis role - you read the multi-AI research and structure it into the specification format.

**NLSpec Template:**

```markdown
# NLSpec: [Project Name]

## Meta
- Version: 1.0.0
- Author: [human author from user context, or "TBD"]
- Created: [today's date]
- Complexity: [clear | complicated | complex - from Step 1]

## Purpose
[1-3 sentences: what this software does and for whom. Derived from user description + probe research.]

## Actors
- **[Actor 1]**: [Role description and capabilities]
- **[Actor 2]**: [Role description and capabilities]
[Include all actors from Step 1 answers + any discovered in research]

## Behaviors

### B1: [Behavior Name]
- **Trigger**: [What initiates this behavior]
- **Preconditions**: [What must be true before execution]
- **Steps**:
  1. [Step 1]
  2. [Step 2]
- **Postconditions**: [What must be true after execution]
- **Edge Cases**:
  - [Edge case]: [Expected handling]

### B2: [Behavior Name]
- **Trigger**: [What initiates this behavior]
- **Preconditions**: [What must be true before execution]
- **Steps**:
  1. [Step 1]
- **Postconditions**: [What must be true after execution]
- **Edge Cases**:
  - [Edge case]: [Expected handling]

[Add as many behaviors as the research and scope warrant. Aim for 3-7 core behaviors.]

## Constraints
- **Performance**: [Latency, throughput requirements]
- **Security**: [Authentication, authorization, data handling]
- **Compatibility**: [APIs, platforms, browsers, versions]
- **Scale**: [Expected load, data volume, growth projections]
[Populate from Step 1 constraint answers + probe research findings]

## Dependencies
- **External Services**: [APIs, databases, third-party services]
- **Libraries/Frameworks**: [Required packages, minimum versions]

## Acceptance Definition
- **Satisfaction Target**: [0.0-1.0, e.g., 0.90 - based on complexity class]
- **Critical Behaviors**: [Which behaviors must achieve 1.0 satisfaction]
```

**Guidelines for synthesis:**
- Use research findings to fill in realistic, specific values (not placeholders)
- Behaviors should be concrete and testable, not vague
- Constraints should have measurable targets where possible
- For "clear" complexity: aim for 0.95 satisfaction target
- For "complicated" complexity: aim for 0.90 satisfaction target
- For "complex" complexity: aim for 0.85 satisfaction target

---

### STEP 7: Validate Completeness (MANDATORY - Validation Gate)

**Check the generated NLSpec for completeness:**

Verify each section:
1. **Purpose** section exists and is non-empty (not placeholder text)
2. **Actors** section has at least 1 actor with description
3. **Behaviors** section has at least 1 behavior with trigger + postconditions
4. **Constraints** section exists with at least 1 constraint category filled
5. **Dependencies** section exists
6. **Acceptance Definition** has a satisfaction target between 0.0 and 1.0

**Calculate completeness score:**
- Total sections: 6 (Purpose, Actors, Behaviors, Constraints, Dependencies, Acceptance)
- Score = sections adequately filled / 6
- Report: "Completeness: X/6 sections (XX%)"

**Flag any issues:**
- Missing sections -> "WARNING: [Section] is missing"
- Weak sections (placeholder text, single word) -> "NOTE: [Section] could be strengthened"
- No edge cases defined -> "NOTE: Consider adding edge cases to behaviors"

**Display validation report to user.**

---

### STEP 8: Save & Update State (MANDATORY)

**Save the NLSpec:**

Default filename: `spec.md` in the current working directory.
If user specified a different filename, use that instead.

```bash
# Write the NLSpec to file (use Write tool, not Bash)
```

**Update state with spec context:**

```bash
# Extract summary for state
spec_summary="NLSpec generated for [project name] with [N] behaviors, complexity: [class]"

# Update spec phase context
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "spec" \
  "$spec_summary"

# Update metrics
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "phases_completed" "1"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "codex"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "gemini"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "claude"
```

**Present final summary to user:**

```
NLSpec saved to: [filename]
Completeness: X/6 sections (XX%)
Behaviors defined: N
Complexity class: [clear|complicated|complex]
Satisfaction target: [0.XX]

Next steps:
- Review and refine the spec manually
- Use /octo:develop to implement from this spec
- Use /octo:embrace for full lifecycle from spec
```

**Include attribution:**
```
---
Multi-AI Research powered by Claude Octopus
Providers: Codex | Gemini | Claude
```

---

## Error Handling

If any step fails:
- **Step 1 (Questions)**: If user declines all questions, proceed with best-effort assumptions and note them
- **Step 2 (Providers)**: If both unavailable, suggest `/octo:setup` and STOP
- **Step 3 (State)**: If state-manager.sh fails, continue without prior state (warn user)
- **Step 4 (orchestrate.sh)**: Show bash error, check logs, report to user. DO NOT substitute with direct research
- **Step 5 (Validation)**: If synthesis missing, show orchestrate.sh logs, DO NOT proceed
- **Step 6 (Synthesis)**: If research is thin, generate NLSpec with what's available and flag weak sections
- **Step 7 (Completeness)**: Always report score, even if low
- **Step 8 (Save)**: If write fails, output NLSpec to chat so user can copy it

---

## Prohibited Actions

- CANNOT skip orchestrate.sh probe execution
- CANNOT simulate or fake multi-AI research
- CANNOT substitute direct Claude analysis for probe results
- CANNOT skip completeness validation
- CANNOT proceed past a failed validation gate
- CANNOT create working/progress files in plugin directory

---

**START WITH STEP 1 CLARIFYING QUESTIONS NOW.**
