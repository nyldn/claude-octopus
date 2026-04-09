---
name: flow-develop
aliases:
  - develop
  - develop-workflow
  - tangle
  - tangle-workflow
description: Multi-AI implementation using Codex and Gemini CLIs (Double Diamond Develop phase)

  DO NOT use for: simple code edits (use Edit tool), reading/reviewing code,
  built-in commands, or trivial single-file changes.

# Claude Code v2.1.12+ Integration
agent: general-purpose
context: fork
task_management: true
task_dependencies:
  - flow-define
execution_mode: enforced
pre_execution_contract:
  - context_detected
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - synthesis_file_exists
trigger: |
  AUTOMATICALLY ACTIVATE when user requests building or implementation:
  - "build X" or "implement Y" or "create Z"
  - "develop a feature for X"
  - "write code to do Y"
  - "add functionality for Z"
  - "generate implementation for X"

  DO NOT activate for:
  - Simple code edits (use Edit tool)
  - Reading or reviewing code (use Read/review skills)
  - Built-in commands (/plugin, /help, etc.)
  - Trivial single-file changes
---

{{PREAMBLE}}

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
  define_status=$("${HOME}/.claude-octopus/plugin/scripts/octo-state.sh" get_phase_status 2)
  if [[ "$define_status" != "complete" ]]; then
    echo "⚠️ Warning: Define phase not marked complete. Consider running definition first."
  fi
fi

# Update state for Development phase
"${HOME}/.claude-octopus/plugin/scripts/octo-state.sh" update_state \
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
SEARCH_PY="${HOME}/.claude-octopus/plugin/vendors/ui-ux-pro-max-skill/src/ui-ux-pro-max/scripts/search.py"
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

**MANDATORY: You MUST use the Bash tool to run this provider check BEFORE displaying the banner. Do NOT skip it. Do NOT assume availability.**

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/helpers/check-providers.sh"
```

**Use the ACTUAL results below. PROHIBITED: Showing only "🔵 Claude: Available ✓" without listing all providers.**


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
"${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" init_state

# Set current workflow
"${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" set_current_workflow "flow-develop" "develop"

# Get prior decisions (critical for implementation)
prior_decisions=$("${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" get_decisions "all")

# Get context from discover and define phases
discover_context=$("${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" get_context "discover")
define_context=$("${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" get_context "define")

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
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh develop "<user's implementation request>"
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
  "${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" write_decision \
    "develop" \
    "$decision_made" \
    "Multi-AI implementation consensus"
fi

# Update develop phase context
"${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" update_context \
  "develop" \
  "$implementation_approach"

# Update metrics
"${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" update_metrics "phases_completed" "1"
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

# Develop Workflow - Develop Phase 🛠️

## ⚠️ MANDATORY: Context Detection & Visual Indicators

**BEFORE executing ANY workflow actions, you MUST:**

### Step 1: Detect Work Context

Analyze the user's prompt and project to determine context:

**Knowledge Context Indicators** (in prompt):
- Deliverable terms: "PRD", "proposal", "presentation", "report", "strategy document", "business case"
- Business terms: "market entry", "competitive analysis", "stakeholder", "executive summary"

**Dev Context Indicators** (in prompt):
- Technical terms: "API", "endpoint", "function", "module", "service", "component"
- Action terms: "implement", "code", "build", "create", "develop" + technical noun

**Also check**: Does the project have `package.json`, `Cargo.toml`, etc.? (suggests Dev Context)

**Step 1b: Detect Dev Subtype** — see EXECUTION CONTRACT Step 1b above for subtype table and quality supplements. Append the matching supplement to the prompt before calling orchestrate.sh.

### Step 2: Output Context-Aware Banner

**For Dev Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
🛠️ [Dev] Develop Phase: [Brief description of what you're building]
📋 Session: ${CLAUDE_SESSION_ID}

Providers:
🔴 Codex CLI - Code generation and patterns
🟡 Gemini CLI - Alternative approaches
🔵 Claude - Integration and quality gates
```

**For Knowledge Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
🛠️ [Knowledge] Develop Phase: [Brief description of deliverable]
📋 Session: ${CLAUDE_SESSION_ID}

Providers:
🔴 Codex CLI - Structure and framework application
🟡 Gemini CLI - Content and narrative development
🔵 Claude - Integration and quality review
```

{{VISUAL_INDICATORS}}

---

**Part of Double Diamond: DEVELOP** (divergent thinking)

```
       DEVELOP (tangle)

        \         /
         \   *   /
          \ * * /
           \   /
            \ /

       Diverge with
        solutions
```

## What This Workflow Does

The **develop** phase generates multiple implementation approaches using external CLI providers:

1. **🔴 Codex CLI** - Implementation-focused, code generation, technical patterns
2. **🟡 Gemini CLI** - Alternative approaches, edge cases, best practices
3. **🔵 Claude (You)** - Integration, refinement, and final implementation

This is the **divergent** phase for solutions - we explore different implementation paths before converging on the best approach.

---

## When to Use Develop

Use develop when you need:

### Dev Context Examples
- **Feature Implementation**: "Build a user authentication system"
- **Code Generation**: "Create an API endpoint for user registration"
- **Complex Builds**: "Implement a caching layer with Redis"
- **Architecture Implementation**: "Create a microservice for payment processing"
- **Integration Work**: "Integrate Stripe payment processing"

### Knowledge Context Examples
- **PRD Creation**: "Build a PRD for the mobile onboarding feature"
- **Strategy Documents**: "Create a market entry strategy for APAC"
- **Business Cases**: "Build a business case for migrating to cloud"
- **Presentations**: "Create an executive presentation on Q2 results"
- **Research Reports**: "Build a competitive analysis report"

**Don't use develop for:**
- Simple one-line code changes (use Edit tool)
- Bug fixes (use debugging skills)
- Code review tasks (use deliver-workflow or review skills)
- Reading or exploring code (use Read tool)
- Simple document edits (use Write tool)

---

## Visual Indicators

Before execution, you'll see:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation
🛠️ Develop Phase: Building and developing solutions

Providers:
🔴 Codex CLI - Code generation and patterns
🟡 Gemini CLI - Alternative approaches
🔵 Claude - Integration and refinement
```

---

## How It Works

### Step 1: Invoke Tangle Phase

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh develop "<user's implementation request>"
```

### Step 2: Multi-Provider Implementation

The orchestrate.sh script will:
1. Call **Codex CLI** with the implementation task
2. Call **Gemini CLI** with the implementation task
3. You (Claude) contribute implementation analysis
4. Synthesize approaches and recommend best path

### Step 3: Review Quality Gates

The tangle phase includes automatic quality validation:
- Code quality checks
- Security scanning
- Best practice validation
- Implementation completeness

### Step 3b: Handle Agent Continuation (v9.5 / CC v2.1.77+)

When orchestrate.sh output contains `AGENT_TEAMS_RESUME:${agent_id}:${task_id}:${role}:${phase}`:

1. Send a message to the existing agent using `SendMessage({to: "${agent_id}", message: "<iteration prompt>"})` — this auto-resumes a stopped agent automatically (CC v2.1.77+)
2. Read the iteration prompt from the resume instruction JSON at `~/.claude-octopus/agent-teams/${task_id}.json`
3. If SendMessage returns an error (agent GC'd or not found), fall back to creating a new agent with the full prompt from the instruction file
4. After the agent responds, store its agentId via: `bridge_store_agent_id(task_id, agent_id)` in the bridge ledger

Note: The `Agent(resume: ...)` parameter was removed in CC v2.1.77. Always use `SendMessage` for agent continuation.

### Step 4: Read Results

Results are saved to:
```
~/.claude-octopus/results/${SESSION_ID}/tangle-synthesis-<timestamp>.md
```

### Step 5: Implement Solution

After reviewing all perspectives, implement the final solution using Write/Edit tools.

---

## Implementation Instructions

When this skill is invoked, follow the EXECUTION CONTRACT above exactly. The contract includes:

1. **Blocking Step 1**: Detect work context (Dev vs Knowledge)
2. **Blocking Step 2**: Check providers, display visual indicators
3. **Blocking Step 3**: Execute orchestrate.sh develop via Bash tool
4. **Blocking Step 4**: Verify synthesis file exists
5. **Step 5**: Present implementation plan, get user confirmation
6. **Step 6**: Implement the solution using Write/Edit tools

Each step is **mandatory and blocking** - you cannot proceed to the next step until the current one completes successfully.

### Task Management Integration

Create tasks to track execution progress:

```javascript
// At start of skill execution
TaskCreate({
  subject: "Execute develop workflow with multi-AI providers",
  description: "Run orchestrate.sh develop for implementation",
  activeForm: "Running multi-AI develop workflow"
})

// Mark in_progress when calling orchestrate.sh
TaskUpdate({taskId: "...", status: "in_progress"})

// Mark completed ONLY after implementation finished
TaskUpdate({taskId: "...", status: "completed"})
```

### Error Handling

If any step fails:
- **Step 1 (Context)**: Default to Dev Context if ambiguous
- **Step 2 (Providers)**: If both unavailable, suggest `/octo:setup` and STOP
- **Step 3 (orchestrate.sh)**: Show bash error, check logs, report to user
- **Step 4 (Validation)**: If synthesis missing, show orchestrate.sh logs, DO NOT substitute with direct implementation

Never fall back to direct implementation if orchestrate.sh execution fails. Report the failure and let the user decide how to proceed.

### Implementation Plan Format

After successful execution, present implementation plan with:
   ```
   # Implementation Plan: <task>

   ## Recommended Approach
   [Your strategic recommendation based on all perspectives]

   ## Implementation Steps
   1. [Step-by-step implementation plan]
   2. ...

   ## Code Overview

   ### Codex Approach
   [Key implementation details from Codex]

   ### Gemini Approach
   [Alternative considerations from Gemini]

   ### Final Implementation
   [Your integrated solution]

   ## Quality Gates
   - [ ] Security validation: PASSED/FAILED
   - [ ] Best practices: PASSED/FAILED
   - [ ] Code quality: PASSED/FAILED

   Would you like me to proceed with implementation?
   ```

6. **Implement the solution**
   After user confirms, use Write/Edit tools to create the implementation:
   - Create necessary files
   - Write code based on synthesized approach
   - Add tests if applicable
   - Document the implementation

---

## Example Usage

### Example 1: Build Authentication System

```
User: Build a user authentication system with JWT

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
🛠️ Develop Phase: Building authentication system

[Executes: ${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh develop "Build a user authentication system with JWT"]

[After completion, reads synthesis and presents:]

# Implementation Plan: User Authentication System

## Recommended Approach

Based on multi-provider analysis, I recommend a layered approach:
1. Auth middleware for JWT validation
2. Login/register endpoints
3. Token refresh mechanism
4. Secure password hashing (bcrypt)

## Implementation Steps

1. Create `src/auth/middleware.ts` - JWT validation middleware
2. Create `src/auth/controller.ts` - Login/register endpoints
3. Create `src/auth/service.ts` - Business logic
4. Create `src/auth/utils.ts` - Token generation/validation
5. Update `src/routes.ts` - Register auth routes

## Code Overview

### Codex Approach
- Modern TypeScript with strict types
- Express middleware pattern
- Redis for token blacklisting
- Comprehensive error handling

### Gemini Approach
- Passport.js integration suggestion
- Rate limiting on auth endpoints
- Multi-factor auth consideration
- Session management alternatives

### Final Implementation
- Hybrid: Modern TypeScript + Express patterns
- JWT with refresh tokens
- bcrypt password hashing
- Rate limiting included
- Optional MFA hooks for future

## Quality Gates
- ✅ Security validation: PASSED (bcrypt, secure tokens)
- ✅ Best practices: PASSED (TypeScript, error handling)
- ⚠️  Code quality: WARNING (consider adding request validation)

Would you like me to proceed with implementation?

[User: Yes, proceed]

[Claude creates files and implements the solution]
```

### Example 2: Create API Endpoint

```
User: Create an API endpoint for fetching user notifications

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
🛠️ Develop Phase: Creating API endpoint

[Executes tangle workflow]

[Presents implementation plan with multi-provider perspectives]
[Implements the endpoint after user confirmation]
```

---

## Quality Gates Integration

The tangle phase automatically runs quality checks via `.claude/hooks/quality-gate.sh`:

```bash
# Triggered after tangle execution (PostToolUse hook)
./hooks/quality-gate.sh
```

{{QUALITY_GATES}}

---

## Integration with Other Workflows

Tangle is the **third phase** of the Double Diamond:

```
PROBE (Discover) → GRASP (Define) → TANGLE (Develop) → INK (Deliver)
```

After tangle completes, you may continue to:
- **Ink**: Validate and deliver the implementation

Or use standalone for implementation tasks.

---

## Before Implementation Checklist

Before writing code, ensure:

- [ ] All providers responded with implementation approaches
- [ ] Quality gates evaluated (security, best practices, code quality)
- [ ] User confirmed the implementation plan
- [ ] File structure and architecture are clear
- [ ] Dependencies identified and available
- [ ] Tests planned (if applicable)

---

## After Implementation: Auto Code Review & E2E Verification (MANDATORY)

**After implementation completes and before presenting results to the user, you MUST launch two verification agents in parallel.** Do NOT skip this step or ask the user whether to run it — it is automatic.

### Launch both agents simultaneously:

**Agent 1 — Code Review (Sonnet):**
```
Agent(
  model: "sonnet",
  subagent_type: "feature-dev:code-reviewer",
  run_in_background: true,
  description: "Code review: post-develop",
  prompt: "Review the code changes from this development session. Focus on:
1. Bugs, logic errors, security vulnerabilities
2. Hidden dependencies or coupling issues
3. Whether error handling covers failure modes
4. Adherence to project conventions (check CLAUDE.md)

Check git diff for the changed files. Report only high-confidence issues."
)
```

**Agent 2 — E2E Verification (Sonnet):**
```
Agent(
  model: "sonnet",
  run_in_background: true,
  description: "E2E test: post-develop",
  prompt: "Run end-to-end verification of the development changes:
1. Run the project's test suite (detect from package.json scripts, Makefile, or pyproject.toml)
2. Verify no regressions in existing tests
3. Check that new files are properly integrated (imported, registered, sourced)
4. Verify the implementation matches the original task requirements

Report: tests passed/failed, any integration issues found."
)
```

**After both agents complete:**
- Present their findings to the user as part of the results
- If the code reviewer found HIGH-confidence issues, flag them prominently
- If tests failed, flag before the "what next?" prompt
- Do NOT block on the review — present findings alongside results

WHY: The user should never have to manually request a code review after development work. Fresh-eyes review from a different model (Sonnet vs Opus) catches issues the implementer is blind to. Running tests automatically catches regressions before the user discovers them.

---

## After Implementation Checklist

After writing code, ensure:

- [ ] All files created/updated
- [ ] Code follows recommended patterns from synthesis
- [ ] Code follows the project's existing commenting conventions (do not add comments unless asked or required by project style)
- [ ] Security concerns addressed
- [ ] Error handling implemented
- [ ] Tests written (if applicable)
- [ ] Lint/typecheck commands run (detect from package.json, pyproject.toml, Cargo.toml, Makefile; if not found, ask the user)
- [ ] If lint/test commands were discovered and not documented in CLAUDE.md, suggest adding them
- [ ] **Auto code review completed** (Sonnet agent)
- [ ] **E2E verification completed** (Sonnet agent)
- [ ] User notified of completion with review findings
- [ ] Suggest running ink-workflow for validation

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
"${HOME}/.claude-octopus/plugin/scripts/octo-state.sh" update_state \
  --status "complete" \
  --history "Develop phase completed"

# Create git checkpoint tag
checkpoint_tag="octo-checkpoint-post-develop-$(date +%Y%m%d-%H%M%S)"
git tag "$checkpoint_tag" -m "Post-develop checkpoint from embrace workflow"
echo "📌 Created checkpoint: $checkpoint_tag"

# Record files modified in this phase
modified_files=$(git diff --name-only HEAD~1 2>/dev/null || echo "See git log")
"${HOME}/.claude-octopus/plugin/scripts/octo-state.sh" update_state \
  --history "Files modified: $modified_files"
```

---

**Ready to build!** This skill activates automatically when users request implementation or building features.
