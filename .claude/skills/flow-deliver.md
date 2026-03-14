---
name: flow-deliver
aliases:
  - deliver
  - deliver-workflow
  - ink
  - ink-workflow
description: Multi-AI validation and review using Codex and Gemini CLIs (Double Diamond Deliver phase)

# Claude Code v2.1.12+ Integration
agent: general-purpose
context: fork
task_management: true
task_dependencies:
  - flow-develop
execution_mode: enforced
pre_execution_contract:
  - context_detected
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - validation_file_exists
trigger: |
  AUTOMATICALLY ACTIVATE when user requests validation or review:
  - "review X" or "validate Y" or "test Z"
  - "check if X works correctly"
  - "verify the implementation of Y"
  - "find issues in Z"
  - "quality check for X"
  - "ensure Y meets requirements"

  DO NOT activate for:
  - Implementation tasks (use tangle-workflow)
  - Research tasks (use probe-workflow)
  - Requirement definition (use grasp-workflow)
  - Built-in commands (/plugin, /help, etc.)
---

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

**Also check**: What is being reviewed? Code files → Dev, Documents → Knowledge

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

**Validation:**
- If BOTH Codex and Gemini unavailable → STOP, suggest: `/octo:setup`
- If ONE unavailable → Continue with available provider(s)
- If BOTH available → Proceed normally

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

# Deliver Workflow - Deliver Phase ✅

## ⚠️ MANDATORY: Context Detection & Visual Indicators

**BEFORE executing ANY workflow actions, you MUST:**

### Step 1: Detect Work Context

Analyze the user's prompt and project to determine context:

**Knowledge Context Indicators** (in prompt):
- Document terms: "report", "presentation", "PRD", "proposal", "document", "brief"
- Quality terms: "argument", "evidence", "clarity", "completeness", "narrative"

**Dev Context Indicators** (in prompt):
- Code terms: "code", "implementation", "API", "endpoint", "function", "module"
- Quality terms: "security", "performance", "tests", "coverage", "bugs"

**Also check**: What is being reviewed? Code files → Dev, Documents → Knowledge

**Step 1b: Detect Dev Subtype** — see EXECUTION CONTRACT Step 1b above for subtype table and validation supplements. Append the matching supplement to the prompt before calling orchestrate.sh.

### Step 2: Output Context-Aware Banner

**For Dev Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation mode
✅ [Dev] Deliver Phase: [Brief description of code review]
📋 Session: ${CLAUDE_SESSION_ID}

Providers:
🔴 Codex CLI - Code quality analysis
🟡 Gemini CLI - Security and edge cases
🔵 Claude - Synthesis and recommendations
```

**For Knowledge Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation mode
✅ [Knowledge] Deliver Phase: [Brief description of document review]
📋 Session: ${CLAUDE_SESSION_ID}

Providers:
🔴 Codex CLI - Structure and logic analysis
🟡 Gemini CLI - Content quality and completeness
🔵 Claude - Synthesis and recommendations
```

**This is NOT optional.** Users need to see which AI providers are active and understand they are being charged for external API calls (🔴 🟡).

---

**Part of Double Diamond: DELIVER** (convergent thinking)

```
        DELIVER (ink)

         \         /
          \       /
           \     /
            \   /
             \ /

          Converge to
           delivery
```

## What This Workflow Does

The **deliver** phase validates and reviews implementations using external CLI providers:

1. **🔴 Codex CLI** - Code quality, best practices, technical correctness
2. **🟡 Gemini CLI** - Security audit, edge cases, user experience
3. **🔵 Claude (You)** - Synthesis and final validation report

This is the **convergent** phase for delivery - we ensure quality before shipping.

---

## When to Use Deliver

Use deliver when you need:

### Dev Context Examples
- **Code Review**: "Review the authentication implementation"
- **Security Audit**: "Check for security vulnerabilities in auth.ts"
- **Quality Validation**: "Validate the API endpoints are production-ready"
- **Implementation Verification**: "Verify the caching layer works correctly"
- **Pre-Deployment Check**: "Ensure the feature is ready to ship"

### Knowledge Context Examples
- **Document Review**: "Review the PRD for completeness"
- **Presentation Validation**: "Check the executive presentation for clarity"
- **Report Quality Check**: "Validate the market analysis report"
- **Proposal Review**: "Review the business case for stakeholder readiness"
- **Content Audit**: "Ensure the strategy document is actionable"

**Don't use deliver for:**
- Building implementations (use develop-workflow)
- Research and exploration (use discover-workflow)
- Requirement definition (use define-workflow)
- Simple code/document reading (use Read tool)

---

## Visual Indicators

Before execution, you'll see:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation
✅ Deliver Phase: Reviewing and validating implementation

Providers:
🔴 Codex CLI - Code quality and best practices
🟡 Gemini CLI - Security and edge cases
🔵 Claude - Synthesis and validation report
```

---

## How It Works

### Step 1: Invoke Ink Phase

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh deliver "<user's validation request>"
```

### Step 2: Multi-Provider Validation

The orchestrate.sh script will:
1. Call **Codex CLI** for code quality analysis
2. Call **Gemini CLI** for security and edge case review
3. You (Claude) synthesize findings into validation report
4. Generate quality scores and recommendations

### Step 3: Quality Gates (Automatic)

The ink phase includes automatic quality validation via PostToolUse hook:
- **Code Quality**: Complexity, maintainability, documentation
- **Security**: OWASP top 10, authentication, input validation
- **Best Practices**: Error handling, logging, testing
- **Completeness**: Missing functionality, edge cases

### Step 4: Read Results

Results are saved to:
```
~/.claude-octopus/results/${SESSION_ID}/ink-validation-<timestamp>.md
```

### Step 5: Present Validation Report

Read the synthesis and present findings with quality scores to the user.

---

## Implementation Instructions

When this skill is invoked, follow the EXECUTION CONTRACT above exactly. The contract includes:

1. **Blocking Step 1**: Detect work context (Dev vs Knowledge)
2. **Blocking Step 2**: Check providers, display visual indicators
3. **Blocking Step 3**: Execute orchestrate.sh deliver via Bash tool
4. **Blocking Step 4**: Verify validation file exists
5. **Step 5**: Present formatted validation report

Each step is **mandatory and blocking** - you cannot proceed to the next step until the current one completes successfully.

### Task Management Integration

Create tasks to track execution progress:

```javascript
// At start of skill execution
TaskCreate({
  subject: "Execute deliver workflow with multi-AI providers",
  description: "Run orchestrate.sh deliver for validation",
  activeForm: "Running multi-AI deliver workflow"
})

// Mark in_progress when calling orchestrate.sh
TaskUpdate({taskId: "...", status: "in_progress"})

// Mark completed ONLY after validation report presented
TaskUpdate({taskId: "...", status: "completed"})
```

### Error Handling

If any step fails:
- **Step 1 (Context)**: Default to Dev Context if ambiguous
- **Step 2 (Providers)**: If both unavailable, suggest `/octo:setup` and STOP
- **Step 3 (orchestrate.sh)**: Show bash error, check logs, report to user
- **Step 4 (Validation)**: If validation file missing, show orchestrate.sh logs, DO NOT substitute with direct review

Never fall back to direct review if orchestrate.sh execution fails. Report the failure and let the user decide how to proceed.

### Validation Report Format

After successful execution, present validation report with:
   ```
   # Validation Report: <task>

   ## Overall Status: ✅ PASSED / ⚠️ PASSED WITH WARNINGS / ❌ FAILED

   **Quality Score**: XX/100

   ## Summary
   [Brief summary of validation findings]

   ## Critical Issues (Must Fix)
   - [ ] Issue 1: [Description]
   - [ ] Issue 2: [Description]

   ## Warnings (Should Fix)
   - [ ] Warning 1: [Description]
   - [ ] Warning 2: [Description]

   ## Recommendations (Nice to Have)
   - [ ] Recommendation 1: [Description]
   - [ ] Recommendation 2: [Description]

   ## Validation Details

   ### Code Quality (Codex Analysis)
   **Score**: XX/100
   - [Specific findings about code quality]
   - [Best practice violations]
   - [Improvement suggestions]

   ### Security Audit (Gemini Analysis)
   **Score**: XX/100
   - [Security vulnerabilities found]
   - [Authentication/authorization issues]
   - [Input validation concerns]

   ### Final Validation (Claude Synthesis)
   **Score**: XX/100
   - [Integrated assessment]
   - [Risk analysis]
   - [Go/no-go recommendation]

   ## Quality Gates
   - [X] Code Quality: XX/100 (PASSED/FAILED)
   - [X] Security: XX/100 (PASSED/FAILED)
   - [X] Best Practices: XX/100 (PASSED/FAILED)
   - [X] Completeness: XX/100 (PASSED/FAILED)

   ## Next Steps
   [Recommended actions based on findings]

   Full validation report saved to: <validation file path>
   ```

---

## Example Usage

### Example 1: Review Authentication Implementation

```
User: Review the authentication implementation in src/auth/

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation
✅ Deliver Phase: Reviewing authentication implementation

[Executes: ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh deliver "Review authentication implementation in src/auth/"]

[After completion, reads validation and presents:]

# Validation Report: Authentication Implementation

## Overall Status: ⚠️ PASSED WITH WARNINGS

**Quality Score**: 78/100

## Summary

The authentication implementation is functional and follows most best practices, but has security concerns with token storage and missing rate limiting. Code quality is good with TypeScript types and error handling. Recommend addressing security warnings before production deployment.

## Critical Issues (Must Fix)
- [ ] **Security**: JWT secret is hardcoded in auth/config.ts (should use env variable)
- [ ] **Security**: No rate limiting on /login endpoint (vulnerability to brute force)

## Warnings (Should Fix)
- [ ] **Best Practice**: Password validation regex could be stronger (min 12 chars, special chars)
- [ ] **Testing**: Missing unit tests for token refresh logic
- [ ] **Error Handling**: Generic error messages leak whether email exists (account enumeration)

## Recommendations (Nice to Have)
- [ ] **UX**: Add "remember me" functionality for longer sessions
- [ ] **Monitoring**: Add logging for failed login attempts
- [ ] **Documentation**: Add JSDoc comments for public API methods

## Validation Details

### Code Quality (Codex Analysis)
**Score**: 85/100

**Strengths**:
- Clean TypeScript with proper types
- Good separation of concerns (controller/service/middleware)
- Proper async/await error handling
- Express middleware pattern used correctly

**Issues**:
- Missing JSDoc documentation
- Some functions exceed 50 lines (refactor recommended)
- No unit tests for edge cases

**Code Examples**:
```typescript
// Good: Proper error handling
try {
  const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '15m' });
  return token;
} catch (error) {
  logger.error('Token generation failed', error);
  throw new AuthError('Failed to generate token');
}

// Issue: Hardcoded secret (security risk)
const JWT_SECRET = 'my-secret-key-123'; // Should be process.env.JWT_SECRET
```

### Security Audit (Gemini Analysis)
**Score**: 68/100

**Critical Vulnerabilities**:
- ❌ Hardcoded JWT secret (HIGH severity)
- ❌ No rate limiting on auth endpoints (MEDIUM severity)
- ❌ Account enumeration via error messages (MEDIUM severity)

**Good Security Practices**:
- ✅ bcrypt password hashing with 12 rounds
- ✅ JWT tokens with short expiration (15min)
- ✅ Refresh token rotation implemented
- ✅ HTTPS-only cookies for token storage

**Recommendations**:
- Use environment variables for secrets
- Add express-rate-limit middleware
- Standardize error messages ("Invalid credentials" for all auth failures)
- Consider adding 2FA hooks for future enhancement

### Final Validation (Claude Synthesis)
**Score**: 78/100

**Risk Assessment**:
- **High**: Hardcoded secrets must be fixed before production
- **Medium**: Rate limiting should be added (prevents abuse)
- **Low**: Missing tests and docs can be addressed post-launch

**Go/No-Go Recommendation**:
- ⚠️ **CONDITIONAL GO**: Fix critical security issues, then ready for production
- Timeline: 2-4 hours to address critical issues
- Post-launch: Address warnings and recommendations in next sprint

**Architecture Assessment**:
- Good: Follows Express.js patterns, scalable design
- Good: Proper separation of concerns
- Improve: Add integration tests for full auth flow

## Quality Gates
- [X] Code Quality: 85/100 ✅ PASSED
- [X] Security: 68/100 ⚠️ WARNING (below 75 threshold)
- [X] Best Practices: 80/100 ✅ PASSED
- [X] Completeness: 75/100 ✅ PASSED (minimum viable)

## Next Steps

1. **Immediate (Before Deploy)**:
   - Fix hardcoded JWT secret → use process.env.JWT_SECRET
   - Add rate limiting → npm install express-rate-limit
   - Standardize error messages → update auth/controller.ts

2. **Short Term (Next Sprint)**:
   - Add unit tests for auth service
   - Improve password validation
   - Add JSDoc documentation

3. **Long Term (Future)**:
   - Add 2FA support
   - Implement "remember me" functionality
   - Add comprehensive logging and monitoring

Full validation report saved to: ~/.claude-octopus/results/abc-123/ink-validation-20250118-145600.md
```

### Example 2: Validate API Endpoints

```
User: Validate the new API endpoints are ready to ship

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation
✅ Deliver Phase: Validating API endpoints

[Executes ink workflow]

[Presents detailed validation with:]
- API contract compliance (OpenAPI/Swagger)
- Error handling coverage
- Security (auth, input validation)
- Performance (query optimization)
- Documentation completeness

[Provides go/no-go decision with quality scores]
```

---

## Quality Gate Integration

The ink phase automatically runs comprehensive quality checks via `.claude/hooks/quality-gate.sh`:

```bash
# Triggered after ink execution (PostToolUse hook)
./hooks/quality-gate.sh
```

**v8.49.0: Project-specific lint/typecheck** (before quality scoring):

Before running conceptual quality gates, detect and run the project's actual lint/typecheck commands:
- Check `package.json` for `lint`, `typecheck`, `tsc`, `check` scripts
- Check for `ruff`, `mypy`, `cargo clippy`, `go vet`, `make lint`
- Report pass/fail results alongside quality gate scores
- If quality commands are discovered but not in CLAUDE.md, suggest adding them

**Quality Dimensions**:

| Dimension | Weight | Criteria |
|-----------|--------|----------|
| **Code Quality** | 25% | Complexity, maintainability, documentation |
| **Security** | 35% | OWASP compliance, auth, input validation |
| **Best Practices** | 20% | Error handling, logging, testing |
| **Completeness** | 20% | Feature completeness, edge cases |

**Scoring Thresholds**:
- **90-100**: Excellent - Ready for production
- **75-89**: Good - Minor improvements recommended
- **60-74**: Acceptable - Address warnings before deploy
- **< 60**: Poor - Critical issues must be fixed

---

## Integration with Other Workflows

Ink is the **final phase** of the Double Diamond:

```
PROBE (Discover) → GRASP (Define) → TANGLE (Develop) → INK (Deliver)
```

**Complete workflow example:**
1. **Probe**: "Research authentication best practices" → Discover options
2. **Grasp**: "Define auth requirements" → Narrow to specific needs
3. **Tangle**: "Implement JWT auth" → Build the solution
4. **Ink**: "Validate auth implementation" → Ensure quality before ship

Or use ink standalone for validation of existing code.

---

## Validation Checklist

Before marking validation complete, ensure:

- [ ] All providers completed their analysis
- [ ] Quality scores calculated for all dimensions
- [ ] Critical issues identified and documented
- [ ] Warnings and recommendations provided
- [ ] Go/no-go decision clearly stated
- [ ] Next steps documented for user
- [ ] Full validation report shared

---

## Cost Awareness

**External API Usage:**
- 🔴 Codex CLI uses your OPENAI_API_KEY (costs apply)
- 🟡 Gemini CLI uses your GEMINI_API_KEY (costs apply)
- 🔵 Claude analysis included with Claude Code

Ink workflows typically cost $0.02-0.08 per validation depending on codebase size and complexity.

---

## Post-Delivery: Route to Ship

After delivery validation completes:
1. Update `.octo/STATE.md`:
   - status: "complete"
   - Add history entry: "All phases complete, ready to ship"
2. Suggest: "Project ready! Run `/octo:ship` to finalize and archive."

```bash
# Update state after Delivery completion
"${CLAUDE_PLUGIN_ROOT}/scripts/octo-state.sh" update_state \
  --status "complete" \
  --history "All phases complete, ready to ship"

# Display completion message with next steps
echo ""
echo "🎉 **EMBRACE WORKFLOW COMPLETE**"
echo ""
echo "All four phases have been completed:"
echo "  ✅ Discover - Research and exploration"
echo "  ✅ Define - Requirements and scope"
echo "  ✅ Develop - Implementation"
echo "  ✅ Deliver - Validation and quality"
echo ""
echo "📦 **Project ready! Run \`/octo:ship\` to finalize and archive.**"
```

---

**Ready to validate!** This skill activates automatically when users request code review, validation, or quality checks.
