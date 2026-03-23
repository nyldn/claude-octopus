---
name: flow-deliver
version: 1.0.0
description: "Run multi-AI validation and quality scoring using Codex and Gemini CLIs for the Double Diamond Deliver phase. Produces validation reports with quality gates and go/no-go recommendations. Use when: user says 'review X', 'validate Y', 'test Z', 'score this', 'quality check', 'validate before shipping', or requests code review or document validation."
---

> This file is generated from a template. Edit the `.tmpl` file, not this file directly.
> Run `scripts/gen-skill-docs.sh` to regenerate after changes.


## Pre-Delivery: State Check

Before starting delivery:
1. Read `.octo/STATE.md` to verify Develop phase complete
2. Update STATE.md:
   - current_phase: 4
   - phase_position: "Delivery"
   - status: "in_progress"

```bash
# Verify Develop phase is complete
if [[ -f ".octo/STATE.md" ]]; then
  develop_status=$("${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" get_phase_status 3)
  if [[ "$develop_status" != "complete" ]]; then
    echo "⚠️ Warning: Develop phase not marked complete. Consider completing development first."
  fi
fi

# Update state for Delivery phase
"${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" update_state \
  --phase 4 \
  --position "Delivery" \
  --status "in_progress"
```

---

## ⚠️ EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

This skill uses **ENFORCED execution mode**. You MUST follow this exact sequence.

### STEP 1: Detect Work Context (MANDATORY)

Analyze the user's prompt and project to determine context:

**Knowledge Context Indicators**:
- Document terms: "report", "presentation", "PRD", "proposal", "document", "brief"
- Quality terms: "argument", "evidence", "clarity", "completeness", "narrative"

**Dev Context Indicators**:
- Code terms: "code", "implementation", "API", "endpoint", "function", "module"
- Quality terms: "security", "performance", "tests", "coverage", "bugs"

**Also check**: What is being reviewed? Code files -> Dev, Documents -> Knowledge

**Capture context_type = "Dev" or "Knowledge"**

#### Step 1b: Detect Dev Subtype (if Dev context)

When context_type is Dev, determine the **subtype** to inject domain-appropriate validation criteria into the review prompt. Append the matching validation supplement after the user's prompt when calling orchestrate.sh in Step 4.

| Subtype | Trigger keywords | Validation supplement |
|---------|-----------------|---------------------|
| `frontend-ui` | "page", "widget", "component", "UI", "HTML", "CSS", "form", "dashboard", "layout" | Verify: all referenced files exist (scripts, stylesheets, images). Check ARIA labels and roles, keyboard navigability, touch target sizes (44px min). Flag innerHTML usage. Confirm progressive enhancement (fallbacks for navigator.share, localStorage, etc). Test self-containment: does this work if opened/run with zero setup? |
| `cli-tool` | "CLI", "command-line", "terminal", "script", "flag", "argument" | Verify: --help flag works, exit codes are meaningful (0/1/2), stderr vs stdout used correctly, argument edge cases handled (missing args, invalid input, --unknown-flag). |
| `api-service` | "API", "endpoint", "REST", "GraphQL", "gRPC", "server", "route" | Verify: input validation at every endpoint, consistent error response format, auth on protected routes, rate limiting considered, schema/contract documented. |
| `infra` | "deploy", "terraform", "docker", "CI", "pipeline", "Kubernetes", "helm" | Verify: operations are idempotent, no hardcoded secrets, rollback path exists, health checks included, destroy operations require confirmation. |
| `data` | "ETL", "pipeline", "migration", "schema", "database", "SQL" | Verify: migrations are reversible, data validation at ingestion, backup strategy documented, no data loss on failure. |
| `general` | Default if no subtype matches | No supplement — use standard review criteria. |

**How to apply:** When calling orchestrate.sh in Step 4, append the validation supplement:
```
orchestrate.sh deliver "<user prompt>\n\nDomain-specific validation criteria:\n<supplement text>"
```

**DO NOT PROCEED TO STEP 2 until context determined.** Context type (Dev vs Knowledge) and dev subtype determine which validation supplements to inject — wrong context produces a review that checks irrelevant criteria.

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
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation mode
✅ [Dev] Deliver Phase: [Brief description of code review]

Provider Availability:
🔴 Codex CLI: ${codex_status} - Code quality analysis
🟡 Gemini CLI: ${gemini_status} - Security and edge cases
🔵 Claude: Available ✓ - Synthesis and recommendations

💰 Estimated Cost: $0.02-0.08
⏱️  Estimated Time: 3-7 minutes
```

**For Knowledge Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation mode
✅ [Knowledge] Deliver Phase: [Brief description of document review]

Provider Availability:
🔴 Codex CLI: ${codex_status} - Structure and logic analysis
🟡 Gemini CLI: ${gemini_status} - Content quality and completeness
🔵 Claude: Available ✓ - Synthesis and recommendations

💰 Estimated Cost: $0.02-0.08
⏱️  Estimated Time: 3-7 minutes
```

**DO NOT PROCEED TO STEP 3 until banner displayed.** The banner shows users which providers will run and what costs they'll incur — starting API calls without this visibility violates cost transparency.

---

### STEP 3: Read Prior State (MANDATORY - State Management)

**Before executing the workflow, read full project context:**

```bash
# Initialize state if needed
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state

# Set current workflow
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" set_current_workflow "flow-deliver" "deliver"

# Get all prior decisions (critical for validation)
prior_decisions=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_decisions "all")

# Get context from all prior phases
discover_context=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_context "discover")
define_context=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_context "define")
develop_context=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_context "develop")

# Display what you found (validation needs full context)
echo "📋 Validation Context Summary:"

if [[ "$discover_context" != "null" ]]; then
  echo "  Discovery: $discover_context"
fi

if [[ "$define_context" != "null" ]]; then
  echo "  Definition: $define_context"
fi

if [[ "$develop_context" != "null" ]]; then
  echo "  Development: $develop_context"
fi

if [[ "$prior_decisions" != "[]" && "$prior_decisions" != "null" ]]; then
  echo "  Decisions to validate against:"
  echo "$prior_decisions" | jq -r '.[] | "    - \(.decision) (\(.phase))"'
fi
```

**This provides full context for validation:**
- Requirements and scope (from define phase)
- Implementation decisions (from develop phase)
- Research findings (from discover phase)
- All architectural decisions to validate against
- If **claude-mem** is installed, its MCP tools (`search`, `timeline`, `get_observations`) are available — use them to check for past delivery issues or quality patterns

**DO NOT PROCEED TO STEP 4 until state read.**

---

### STEP 4: Execute orchestrate.sh deliver (MANDATORY - Use Bash Tool)

**You MUST execute this command via the Bash tool:**

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh deliver "<user's validation request>"
```

**CRITICAL: You are PROHIBITED from:**
- ❌ Reviewing directly without calling orchestrate.sh — adversarial multi-AI review catches blind spots that a single reviewer misses; Codex finds code quality issues while Gemini catches security and edge cases
- ❌ Doing single-perspective analysis instead of multi-provider
- ❌ Claiming you're "simulating" the workflow
- ❌ Proceeding to Step 4 without running this command

**You MUST use the Bash tool to invoke orchestrate.sh.**

#### What Users See During Execution (v7.16.0+)

If running in Claude Code v2.1.16+, users will see **real-time progress indicators** in the task spinner:

**Phase 1 - External Provider Execution (Parallel):**
- 🔴 Analyzing code quality and patterns (Codex)...
- 🟡 Validating security and edge cases (Gemini)...

**Phase 2 - Synthesis (Sequential):**
- 🔵 Synthesizing validation results...

These spinner verb updates happen automatically - orchestrate.sh calls `update_task_progress()` before each agent execution. Users see exactly which provider is working and what it's doing.

**If NOT running in Claude Code v2.1.16+:** Progress indicators are silently skipped, no errors shown.

---

### STEP 5: Verify Execution (MANDATORY - Validation Gate)

**After orchestrate.sh completes, verify it succeeded:**

```bash
# Find the latest validation file (created within last 10 minutes)
VALIDATION_FILE=$(find ~/.claude-octopus/results -name "ink-validation-*.md" -mmin -10 2>/dev/null | head -n1)

if [[ -z "$VALIDATION_FILE" ]]; then
  echo "❌ VALIDATION FAILED: No validation file found"
  echo "orchestrate.sh did not execute properly"
  exit 1
fi

echo "✅ VALIDATION PASSED: $VALIDATION_FILE"
cat "$VALIDATION_FILE"
```

**If validation fails:**
1. Report error to user
2. Show logs from `~/.claude-octopus/logs/`
3. DO NOT proceed with presenting results
4. DO NOT substitute with direct review — fallback to single-model review defeats the adversarial multi-provider validation that catches blind spots

---

### STEP 6: Update State (MANDATORY - Post-Execution)

**After validation is complete, record final metrics:**

```bash
# Update deliver phase context with validation summary
validation_summary=$(head -30 "$VALIDATION_FILE" | grep -A 2 "## Summary\|Pass\|Fail" | tail -2 | tr '\n' ' ')

"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "deliver" \
  "$validation_summary"

# Update final metrics (completion of full workflow)
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "phases_completed" "1"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "codex"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "gemini"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics "provider" "claude"

# Display final state summary
echo ""
echo "📊 Session Complete - Final Metrics:"
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" show_summary
```

**DO NOT PROCEED TO STEP 7 until state updated.**

---

### STEP 7: Present Validation Report & Post to PR (Only After Steps 1-6 Complete)

Read the validation file and present:
- Overall status (✅ PASSED / ⚠️ PASSED WITH WARNINGS / ❌ FAILED)
- Quality score (XX/100)
- Summary
- Critical issues (must fix)
- Warnings (should fix)
- Recommendations (nice to have)
- Validation details from all providers
- Quality gates results
- Next steps

**Include attribution:**
```
---
*Multi-AI Validation powered by Claude Octopus*
*Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude*
*Full validation report: $VALIDATION_FILE*
```

#### Post to PR (v8.44.0)

After presenting the report, check if the current branch has an open PR and post the validation summary as a PR comment:

```bash
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
PR_NUM=""

if [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
    if command -v gh &>/dev/null; then
        PR_NUM=$(gh pr list --head "$CURRENT_BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
    fi
fi

if [[ -n "$PR_NUM" ]]; then
    # Extract summary section from validation file for PR comment
    REVIEW_SUMMARY=$(head -60 "$VALIDATION_FILE")

    gh pr comment "$PR_NUM" --body "## Deliver Phase — Validation Report

${REVIEW_SUMMARY}

---
*Multi-AI validation by Claude Octopus (/octo:deliver)*
*Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude*"

    echo "Validation report posted to PR #${PR_NUM}"

    # Update agent registry
    REGISTRY="${CLAUDE_PLUGIN_ROOT}/scripts/agent-registry.sh"
    if [[ -x "$REGISTRY" ]]; then
        AGENT_ID="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
        "$REGISTRY" update "$AGENT_ID" --pr "$PR_NUM" 2>/dev/null || true
    fi
fi
```

**Behavior:**
- Auto-posts when running inside `/octo:embrace` or `/octo:factory`
- When running standalone via `/octo:deliver`, asks user first:
  ```
  "PR #N found. Post validation report as a PR comment?"
  Options: "Yes, post to PR", "No, terminal only"
  ```
- If no PR or `gh` CLI unavailable, skips silently

---

## Providers

| Indicator | Provider | Role (Dev) | Role (Knowledge) | Cost Source |
|-----------|----------|-----------|-------------------|-------------|
| 🔴 | Codex CLI | Code quality analysis | Structure and logic | User's OPENAI_API_KEY |
| 🟡 | Gemini CLI | Security and edge cases | Content quality | User's GEMINI_API_KEY |
| 🔵 | Claude | Synthesis and recommendations | Synthesis and recommendations | Included |

---

## Quality Gate Dimensions

| Dimension | Weight | Criteria |
|-----------|--------|----------|
| **Code Quality** | 25% | Complexity, maintainability, documentation |
| **Security** | 35% | OWASP compliance, auth, input validation |
| **Best Practices** | 20% | Error handling, logging, testing |
| **Completeness** | 20% | Feature completeness, edge cases |

**Thresholds:** 90-100 Excellent (production-ready), 75-89 Good (minor improvements), 60-74 Acceptable (fix warnings), <60 Poor (fix critical issues).

v8.49.0: Also runs project-specific lint/typecheck commands (package.json scripts, ruff, mypy, cargo clippy, etc.) before quality scoring.

---

## Integration

Part of Double Diamond: `PROBE (Discover) → GRASP (Define) → TANGLE (Develop) → INK (Deliver)`

Can also be used standalone for validation of existing code/documents.

**Cost:** $0.02-0.08 per validation depending on codebase size.

## Post-Delivery

After validation completes, update `.octo/STATE.md` with completion and suggest `/octo:ship` to finalize.
