---
name: flow-define
version: 1.0.0
description: "Run multi-AI requirements scoping and problem definition using Codex and Gemini CLIs for the Double Diamond Define phase. Produces prioritized requirements, constraints, and edge cases. Use when: user says 'define the requirements for X', 'clarify the scope of Y', 'what are the constraints for Z', or needs requirement definition, scope clarification, or edge case analysis."
---

> This file is generated from a template. Edit the `.tmpl` file, not this file directly.
> Run `scripts/gen-skill-docs.sh` to regenerate after changes.


## Pre-Definition: State Check

Before starting definition:
1. Read `.octo/STATE.md` to verify Discover phase complete
2. Update STATE.md:
   - current_phase: 2
   - phase_position: "Definition"
   - status: "in_progress"

```bash
# Verify Discover phase is complete
if [[ -f ".octo/STATE.md" ]]; then
  discover_status=$("${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" get_phase_status 1)
  if [[ "$discover_status" != "complete" ]]; then
    echo "⚠️ Warning: Discover phase not marked complete. Consider running discovery first."
  fi
fi

# Update state for Definition phase
"${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" update_state \
  --phase 2 \
  --position "Definition" \
  --status "in_progress"
```

---

## ⚠️ EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

This skill uses **ENFORCED execution mode**. You MUST follow this exact sequence.

### STEP 1: Display Visual Indicators (MANDATORY - BLOCKING)

**Check provider availability:**

```bash
command -v codex &> /dev/null && codex_status="Available ✓" || codex_status="Not installed ✗"
command -v gemini &> /dev/null && gemini_status="Available ✓" || gemini_status="Not installed ✗"
```

**Validation:**
- If BOTH Codex and Gemini unavailable -> STOP, suggest: `/octo:setup`
- If ONE unavailable -> Continue with available provider(s)
- If BOTH available -> Proceed normally


**Display this banner BEFORE orchestrate.sh execution:**

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider definition mode
🎯 Define Phase: [Brief description of what you're defining/scoping]

Provider Availability:
🔴 Codex CLI: ${codex_status} - Technical requirements analysis
🟡 Gemini CLI: ${gemini_status} - Business context and constraints
🔵 Claude: Available ✓ - Consensus building and synthesis

💰 Estimated Cost: $0.01-0.05
⏱️  Estimated Time: 2-5 minutes
```

**DO NOT PROCEED TO STEP 2 until banner displayed.** The banner shows users which providers will run and what costs they'll incur — starting API calls without this visibility violates cost transparency.

---

### STEP 2: Read Prior State (MANDATORY - State Management)

**Before executing the workflow, read any prior context:**

```bash
# Initialize state if needed
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state

# Set current workflow
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" set_current_workflow "flow-define" "define"

# Get prior decisions (if any)
prior_decisions=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_decisions "all")

# Get context from discover phase
discover_context=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_context "discover")

# Display what you found (if any)
if [[ "$discover_context" != "null" ]]; then
  echo "📋 Building on discovery findings:"
  echo "  $discover_context"
fi

if [[ "$prior_decisions" != "[]" && "$prior_decisions" != "null" ]]; then
  echo "📋 Respecting prior decisions:"
  echo "$prior_decisions" | jq -r '.[] | "  - \(.decision) (\(.phase)): \(.rationale)"'
fi
```

**This provides context from:**
- Discovery phase research (if completed)
- Prior architectural decisions
- User vision captured earlier
- If **claude-mem** is installed, its MCP tools (`search`, `timeline`, `get_observations`) are available — use them to find past decisions on similar topics

**DO NOT PROCEED TO STEP 3 until state read.**

---

### STEP 3: Phase Discussion - Capture User Vision (MANDATORY - Context Gathering)

**Before executing expensive multi-AI orchestration, capture the user's vision to scope the work effectively.**

**Ask clarifying questions using AskUserQuestion:**

```
Use AskUserQuestion tool to ask:

1. **User Experience**
   Question: "How should users interact with this feature?"
   Header: "User Flow"
   Options:
   - label: "API-first (programmatic access)"
     description: "Build API endpoints first, UI later"
   - label: "UI-first (user-facing interface)"
     description: "Build user interface first, API supports it"
   - label: "Both simultaneously"
     description: "Develop API and UI in parallel"
   - label: "Not applicable"
     description: "This feature doesn't have a user interaction"

2. **Implementation Approach**
   Question: "What technical approach do you prefer?"
   Header: "Approach"
   Options:
   - label: "Fastest to market"
     description: "Prioritize speed, use existing libraries"
   - label: "Most maintainable"
     description: "Focus on clean architecture, may take longer"
   - label: "Best performance"
     description: "Optimize for speed and efficiency"
   - label: "Multi-LLM debate (Claude + Codex + Gemini)"
     description: "Three AI models debate the best approach — uses external API credits"

3. **Scope Boundaries**
   Question: "What's explicitly OUT of scope for this phase?"
   Header: "Out of Scope"
   Options:
   - label: "Testing and QA"
     description: "Focus on implementation, test later"
   - label: "Performance optimization"
     description: "Get it working first, optimize later"
   - label: "Edge cases"
     description: "Handle happy path only initially"
   - label: "Nothing excluded"
     description: "Everything is in scope"
   multiSelect: true
```

**If user selected "Multi-LLM debate (Claude + Codex + Gemini)" for approach:**
Before proceeding with orchestrate.sh, run a Multi-LLM debate to determine the technical approach:
```
/octo:debate --rounds 2 --debate-style collaborative "What is the best technical approach for [feature]? Consider: speed to market, maintainability, performance, and the existing codebase patterns."
```
Use the debate synthesis to set the approach context for the Define phase.

**After gathering answers, create context file:**

```bash
# Source context manager
source "${CLAUDE_PLUGIN_ROOT}/scripts/context-manager.sh"

# Extract user answers from AskUserQuestion results
user_flow="[Answer from question 1]"
approach="[Answer from question 2]"
out_of_scope="[Answer from question 3]"

# Create context file with user vision
create_templated_context \
  "define" \
  "$(echo "$USER_REQUEST" | head -c 50)..." \
  "User wants: $user_flow approach with $approach priority" \
  "$approach" \
  "Implementation of requested feature" \
  "$out_of_scope"

echo "📋 Context captured and saved to .claude-octopus/context/define-context.md"
```

**This context will be used to:**
- Scope the multi-AI research (discover phase)
- Focus the requirements definition (define phase)
- Guide implementation decisions (develop phase)
- Validate against user expectations (deliver phase)

**DO NOT PROCEED TO STEP 4 until context captured.** User vision (UX approach, priorities, out-of-scope items) scopes the multi-AI research — without it, providers research too broadly and the definition misses the user's actual intent.

---

### STEP 4: Execute orchestrate.sh define (MANDATORY - Use Bash Tool)

**You MUST execute this command via the Bash tool:**

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh define "<user's clarification request>"
```

**CRITICAL: You are PROHIBITED from:**
- ❌ Defining requirements directly without calling orchestrate.sh — single-model analysis misses the technical-vs-business perspective split that Codex and Gemini provide, producing requirements with blind spots
- ❌ Using direct analysis instead of orchestrate.sh
- ❌ Claiming you're "simulating" the workflow
- ❌ Proceeding to Step 3 without running this command

**You MUST use the Bash tool to invoke orchestrate.sh.**

#### What Users See During Execution (v7.16.0+)

If running in Claude Code v2.1.16+, users will see **real-time progress indicators** in the task spinner:

**Phase 1 - External Provider Execution (Parallel):**
- 🔴 Analyzing technical requirements (Codex)...
- 🟡 Clarifying user needs and context (Gemini)...

**Phase 2 - Synthesis (Sequential):**
- 🔵 Building consensus on problem definition...

These spinner verb updates happen automatically - orchestrate.sh calls `update_task_progress()` before each agent execution. Users see exactly which provider is working and what it's doing.

**If NOT running in Claude Code v2.1.16+:** Progress indicators are silently skipped, no errors shown.

---

### STEP 5: Verify Execution (MANDATORY - Validation Gate)

**After orchestrate.sh completes, verify it succeeded:**

```bash
# Find the latest synthesis file (created within last 10 minutes)
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "grasp-synthesis-*.md" -mmin -10 2>/dev/null | head -n1)

if [[ -z "$SYNTHESIS_FILE" ]]; then
  echo "❌ VALIDATION FAILED: No synthesis file found"
  echo "orchestrate.sh did not execute properly"
  exit 1
fi

echo "✅ VALIDATION PASSED: $SYNTHESIS_FILE"
cat "$SYNTHESIS_FILE"
```

**If validation fails:**
1. Report error to user
2. Show logs from `~/.claude-octopus/logs/`
3. DO NOT proceed with presenting results
4. DO NOT substitute with direct analysis — fallback to single-model analysis defeats the purpose of multi-provider consensus and produces narrower requirements

---

### STEP 6: Update State (MANDATORY - Post-Execution)

**After synthesis is verified, record findings and decisions in state:**

```bash
# Extract key definition from synthesis
key_definition=$(head -50 "$SYNTHESIS_FILE" | grep -A 3 "## Problem Definition\|## Summary" | tail -3 | tr '\n' ' ')

# Record any architectural decisions made
# (You should identify these from the synthesis - e.g., tech stack, approach, patterns)
decision_made=$(echo "$key_definition" | grep -o "decided to\|chose to\|selected\|using [A-Za-z0-9 ]*" | head -1)

if [[ -n "$decision_made" ]]; then
  "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_decision \
    "define" \
    "$decision_made" \
    "Consensus from multi-AI definition phase"
fi

# Update define phase context
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "define" \
  "$key_definition"

# Update metrics
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "phases_completed" "1"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "codex"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "gemini"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "claude"
```

**DO NOT PROCEED TO STEP 7 until state updated.**

---

### STEP 7: Present Problem Definition (Only After Steps 1-6 Complete)

Read the synthesis file and present:
- Core requirements (must have, should have, nice to have)
- Technical constraints
- User needs
- Edge cases to handle
- Out of scope items
- Perspectives from all providers
- Requirements checklist
- Next steps (usually tangle phase for implementation)

**Include attribution:**
```
---
*Multi-AI Problem Definition powered by Claude Octopus*
*Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude*
*Full problem definition: $SYNTHESIS_FILE*
```

---

## Providers

| Indicator | Provider | Role | Cost Source |
|-----------|----------|------|-------------|
| 🔴 | Codex CLI | Technical requirements, edge cases, constraints | User's OPENAI_API_KEY |
| 🟡 | Gemini CLI | User needs, business requirements, context | User's GEMINI_API_KEY |
| 🔵 | Claude | Problem synthesis and requirement definition | Included |

---

## Error Handling

- **Providers unavailable:** If both Codex and Gemini missing, suggest `/octo:setup` and STOP
- **orchestrate.sh fails:** Show error, check logs, report to user. DO NOT substitute with direct analysis
- **Synthesis missing:** Show orchestrate.sh logs, do not fall back

## Integration

Part of Double Diamond: `PROBE (Discover) → GRASP (Define) → TANGLE (Develop) → INK (Deliver)`

Can also be used standalone when requirements are unclear. **Cost:** $0.01-0.05 per task.

## Post-Definition

Update `.octo/STATE.md` with completion and populate `.octo/ROADMAP.md` with defined phases and success criteria.
