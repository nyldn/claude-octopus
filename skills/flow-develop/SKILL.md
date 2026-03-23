---
name: flow-develop
version: 1.0.0
description: "Multi-AI implementation orchestrating Codex, Gemini, and Claude for the Double Diamond Develop phase. Use when: user says 'build X', 'implement Y', 'create Z', 'develop a feature', or requests feature implementation, code generation, or architecture builds. Detects Dev vs Knowledge context to tailor provider prompts."
---

> This file is generated from a template. Edit the `.tmpl` file, not this file directly.
> Run `scripts/gen-skill-docs.sh` to regenerate after changes.


## Pre-Development: State Check

Before starting development:
1. Read `.octo/STATE.md` to verify Define phase complete
2. Update STATE.md:
   - current_phase: 3
   - phase_position: "Development"
   - status: "in_progress"

```bash
# Verify Define phase is complete
if [[ -f ".octo/STATE.md" ]]; then
  define_status=$("${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" get_phase_status 2)
  if [[ "$define_status" != "complete" ]]; then
    echo "⚠️ Warning: Define phase not marked complete. Consider running definition first."
  fi
fi

# Update state for Development phase
"${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" update_state \
  --phase 3 \
  --position "Development" \
  --status "in_progress"
```

---

## ⚠️ EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

This skill uses **ENFORCED execution mode**. You MUST follow this exact sequence.

### STEP 1: Detect Work Context (MANDATORY)

Analyze the user's prompt and project to determine context:

**Knowledge Context Indicators**:
- Deliverable terms: "PRD", "proposal", "presentation", "report", "strategy document", "business case"
- Business terms: "market entry", "competitive analysis", "stakeholder", "executive summary"

**Dev Context Indicators**:
- Technical terms: "API", "endpoint", "function", "module", "service", "component"
- Action terms: "implement", "code", "build", "create", "develop" + technical noun

**Also check**: Does project have `package.json`, `Cargo.toml`, etc.? (suggests Dev Context)

**Capture context_type = "Dev" or "Knowledge"**

#### Step 1b: Detect Dev Subtype (if Dev context)

When context_type is Dev, determine the **subtype** to inject domain-appropriate quality guidance into the prompt sent to providers. Append the matching supplement text after the user's prompt.

| Subtype | Trigger keywords | Quality supplement |
|---------|-----------------|-------------------|
| `frontend-ui` | "page", "widget", "component", "UI", "HTML", "CSS", "form", "dashboard", "layout" | See **frontend-ui enrichment** below. |
| `cli-tool` | "CLI", "command-line", "terminal", "script", "flag", "argument" | Help text via --help flag. Meaningful exit codes (0 success, 1 user error, 2 system error). Stdin/stdout/stderr used correctly. Argument validation with clear error messages. |
| `api-service` | "API", "endpoint", "REST", "GraphQL", "gRPC", "server", "route" | Input validation at boundaries. Consistent error response format. Auth/authz on every endpoint. Rate limiting consideration. OpenAPI/schema documentation. |
| `infra` | "deploy", "terraform", "docker", "CI", "pipeline", "Kubernetes", "helm" | Idempotent operations. Secrets never hardcoded. Rollback path documented. Health checks included. |
| `data` | "ETL", "pipeline", "migration", "schema", "database", "SQL" | Idempotent migrations. Backup/rollback strategy. Data validation at ingestion. |
| `general` | Default if no subtype matches | No supplement — use base implementer persona only. |

#### frontend-ui enrichment

When `frontend-ui` subtype is detected, do TWO things:

**A. Inject quality supplement into the prompt:**
Self-contained files preferred. Accessibility: ARIA labels, keyboard nav, 44px touch targets (WCAG 2.5.5). Safe DOM: createElement over innerHTML. Progressive enhancement: feature-detect APIs (navigator.share, localStorage) with fallbacks. Persist user prefs via localStorage.

**B. Pull design intelligence from BM25 (if available):**

Before calling orchestrate.sh, check if the design intelligence engine exists and query it for relevant design context:

```bash
SEARCH_PY="${CLAUDE_PLUGIN_ROOT}/vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py"
if [[ -f "$SEARCH_PY" ]]; then
    # Detect relevant domains from the prompt
    design_context=""
    # Style query — what visual style fits this task?
    style_hit=$(python3 "$SEARCH_PY" "<user's task description>" --domain style --top 1 2>/dev/null || true)
    [[ -n "$style_hit" ]] && design_context+="Design style suggestion: $style_hit\n"
    # UX query — relevant UX patterns
    ux_hit=$(python3 "$SEARCH_PY" "<user's task description>" --domain ux --top 1 2>/dev/null || true)
    [[ -n "$ux_hit" ]] && design_context+="UX pattern: $ux_hit\n"
    # Append to prompt if hits found
    if [[ -n "$design_context" ]]; then
        # Append design intelligence to the orchestrate.sh prompt
        prompt="${prompt}\n\nDesign intelligence (from BM25 search):\n${design_context}"
    fi
fi
```

This gives providers concrete design guidance (style direction, UX patterns) without requiring the user to run `/octo:design-ui-ux` separately. If the search engine isn't installed, implementation proceeds with the quality supplement only.

**How to apply:** When calling orchestrate.sh in Step 4, append the quality supplement (and design intelligence if available) to the prompt:
```
orchestrate.sh develop "<user prompt>\n\nQuality requirements for this deliverable:\n<supplement text>\n<design intelligence if found>"
```

**DO NOT PROCEED TO STEP 2 until context determined.** Context type (Dev vs Knowledge) and dev subtype determine which quality supplements and design intelligence to inject — wrong context wastes provider credits on irrelevant analysis.

---

### STEP 2: Display Visual Indicators (MANDATORY - BLOCKING)

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

**For Dev Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
🛠️ [Dev] Develop Phase: [Brief description of what you're building]

Provider Availability:
🔴 Codex CLI: ${codex_status} - Code generation and patterns
🟡 Gemini CLI: ${gemini_status} - Alternative approaches
🔵 Claude: Available ✓ - Integration and quality gates

💰 Estimated Cost: $0.02-0.10
⏱️  Estimated Time: 3-7 minutes
```

**For Knowledge Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
🛠️ [Knowledge] Develop Phase: [Brief description of deliverable]

Provider Availability:
🔴 Codex CLI: ${codex_status} - Structure and framework application
🟡 Gemini CLI: ${gemini_status} - Content and narrative development
🔵 Claude: Available ✓ - Integration and quality review

💰 Estimated Cost: $0.02-0.10
⏱️  Estimated Time: 3-7 minutes
```

**DO NOT PROCEED TO STEP 3 until banner displayed.** The banner shows users which providers will run and what costs they'll incur — starting API calls without this visibility violates cost transparency.

---

### STEP 3: Read Prior State (MANDATORY - State Management)

**Before executing the workflow, read any prior context:**

```bash
# Initialize state if needed
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state

# Set current workflow
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" set_current_workflow "flow-develop" "develop"

# Get prior decisions (critical for implementation)
prior_decisions=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_decisions "all")

# Get context from discover and define phases
discover_context=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_context "discover")
define_context=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_context "define")

# Display what you found (if any)
if [[ "$discover_context" != "null" ]]; then
  echo "📋 Discovery phase findings:"
  echo "  $discover_context"
fi

if [[ "$define_context" != "null" ]]; then
  echo "📋 Definition phase scope:"
  echo "  $define_context"
fi

if [[ "$prior_decisions" != "[]" && "$prior_decisions" != "null" ]]; then
  echo "📋 Implementing with decisions:"
  echo "$prior_decisions" | jq -r '.[] | "  - \(.decision) (\(.phase)): \(.rationale)"'
fi
```

**This provides critical context for implementation:**
- Technology stack and patterns decided
- Scope and requirements defined
- Research findings to inform implementation
- If **claude-mem** is installed, its MCP tools (`search`, `timeline`, `get_observations`) are available — use them to check for related past implementation patterns

**DO NOT PROCEED TO STEP 4 until state read.**

---

### STEP 4: Execute orchestrate.sh develop (MANDATORY - Use Bash Tool)

**You MUST execute this command via the Bash tool:**

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh develop "<user's implementation request>"
```

**CRITICAL: You are PROHIBITED from:**
- ❌ Implementing directly without calling orchestrate.sh — single-model implementation misses alternative approaches and edge cases that Codex and Gemini surface through independent analysis
- ❌ Writing code without multi-provider perspectives
- ❌ Claiming you're "simulating" the workflow
- ❌ Proceeding to Step 4 without running this command

**You MUST use the Bash tool to invoke orchestrate.sh.**

#### What Users See During Execution (v7.16.0+)

If running in Claude Code v2.1.16+, users will see **real-time progress indicators** in the task spinner:

**Phase 1 - External Provider Execution (Parallel):**
- 🔴 Generating code and patterns (Codex)...
- 🟡 Exploring alternative approaches (Gemini)...

**Phase 2 - Synthesis (Sequential):**
- 🔵 Integrating and applying quality gates...

These spinner verb updates happen automatically - orchestrate.sh calls `update_task_progress()` before each agent execution. Users see exactly which provider is working and what it's doing.

**If NOT running in Claude Code v2.1.16+:** Progress indicators are silently skipped, no errors shown.

---

### STEP 5: Verify Execution (MANDATORY - Validation Gate)

**After orchestrate.sh completes, verify it succeeded:**

```bash
# Find the latest synthesis file (created within last 10 minutes)
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "tangle-synthesis-*.md" -mmin -10 2>/dev/null | head -n1)

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
4. DO NOT substitute with direct implementation — fallback to single-model implementation skips the multi-provider synthesis that catches design flaws early

---

### STEP 6: Update State (MANDATORY - Post-Execution)

**After synthesis is verified, record implementation details in state:**

```bash
# Extract key implementation decisions from synthesis
implementation_approach=$(head -50 "$SYNTHESIS_FILE" | grep -A 3 "## Implementation\|## Approach" | tail -3 | tr '\n' ' ')

# Record implementation decisions
decision_made=$(echo "$implementation_approach" | grep -o "implemented\|using [A-Za-z0-9 ]*\|chose to\|pattern:" | head -1)

if [[ -n "$decision_made" ]]; then
  "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_decision \
    "develop" \
    "$decision_made" \
    "Multi-AI implementation consensus"
fi

# Update develop phase context
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "develop" \
  "$implementation_approach"

# Update metrics
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "phases_completed" "1"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "codex"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "gemini"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "claude"
```

**DO NOT PROCEED TO STEP 7 until state updated.**

---

### STEP 7: Present Implementation Plan (Only After Steps 1-6 Complete)

Read the synthesis file and present:
- Recommended approach
- Implementation steps
- Code overview from all perspectives (Codex, Gemini, Claude)
- Quality gates results
- Request user confirmation before implementing

**After user confirms, STEP 6: Implement the solution using Write/Edit tools**

**Include attribution:**
```
---
*Multi-AI Implementation powered by Claude Octopus*
*Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude*
*Full implementation plan: $SYNTHESIS_FILE*
```

---

---

**Part of Double Diamond: DEVELOP** (divergent phase for solutions)

Providers: 🔴 Codex CLI (code generation), 🟡 Gemini CLI (alternative approaches), 🔵 Claude (integration and quality gates).

## When to Use

**Dev Context:** feature implementation, code generation, complex builds, architecture, integration work.
**Knowledge Context:** PRDs, strategy documents, business cases, presentations, research reports.

**Do NOT use for:** simple one-line edits, bug fixes (use debugging skills), code review (use deliver-workflow), reading/exploring code.

## Agent Continuation (v9.5 / CC v2.1.77+)

When orchestrate.sh output contains `AGENT_TEAMS_RESUME:${agent_id}:${task_id}:${role}:${phase}`, use `SendMessage` to resume the agent. Fall back to creating a new agent if SendMessage fails.

---

## Implementation Instructions

Follow the EXECUTION CONTRACT above exactly. Each step is **mandatory and blocking**.

### Error Handling

- **Context detection**: Default to Dev Context if ambiguous
- **Providers unavailable**: If both unavailable, suggest `/octo:setup` and STOP
- **orchestrate.sh fails**: Show error, check logs, report to user. Never fall back to direct implementation.
- **Synthesis missing**: Show logs, DO NOT substitute with direct implementation

### Implementation Plan Format

After successful execution, present: Recommended Approach, Implementation Steps, Code Overview (Codex/Gemini/Final), Quality Gates (security/best practices/code quality), then ask for user confirmation before implementing.

---

## Quality Gates

Automatically runs via `.claude/hooks/quality-gate.sh` with dimensions: Code Quality (25%), Security (35%), Best Practices (20%), Completeness (20%). Scores: 90-100 production-ready, 75-89 minor improvements, 60-74 address warnings, <60 critical fixes needed.

## Workflow Position

Third phase of Double Diamond: `PROBE (Discover) → GRASP (Define) → TANGLE (Develop) → INK (Deliver)`. After completion, continue to Ink phase or use standalone.

---

## After Implementation: Auto Code Review & E2E Verification (MANDATORY)

**Launch two Sonnet agents in parallel immediately after implementation — do NOT skip or ask.**

1. **Code Review Agent**: Review git diff for bugs, security vulnerabilities, coupling issues, convention adherence. Report high-confidence issues only.
2. **E2E Verification Agent**: Run test suite, verify no regressions, check new files are integrated, confirm implementation matches requirements.

Present findings alongside results. Flag high-confidence issues prominently. If tests failed, flag before "what next?" prompt.

## After Implementation Checklist

- All files created/updated following synthesis patterns and project commenting conventions
- Security concerns addressed, error handling implemented
- Lint/typecheck commands run (detect from package.json, pyproject.toml, Cargo.toml, Makefile)
- Auto code review and E2E verification completed
- Suggest running ink-workflow for validation

---

## Cost Awareness

**External API Usage:**
- 🔴 Codex CLI uses your OPENAI_API_KEY (costs apply)
- 🟡 Gemini CLI uses your GEMINI_API_KEY (costs apply)
- 🔵 Claude analysis included with Claude Code

Tangle workflows typically cost $0.02-0.10 per task depending on complexity and code length.

---

## Post-Development: Checkpoint

After development completes:
1. Update `.octo/STATE.md` with completion
2. Create checkpoint: `git tag octo-checkpoint-post-develop-$(date +%Y%m%d-%H%M%S)`
3. Add history entry with files modified

```bash
# Update state after Development completion
"${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" update_state \
  --status "complete" \
  --history "Develop phase completed"

# Create git checkpoint tag
checkpoint_tag="octo-checkpoint-post-develop-$(date +%Y%m%d-%H%M%S)"
git tag "$checkpoint_tag" -m "Post-develop checkpoint from embrace workflow"
echo "📌 Created checkpoint: $checkpoint_tag"

# Record files modified in this phase
modified_files=$(git diff --name-only HEAD~1 2>/dev/null || echo "See git log")
"${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" update_state \
  --history "Files modified: $modified_files"
```

---

**Ready to build!** This skill activates automatically when users request implementation or building features.
