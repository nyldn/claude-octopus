---
name: flow-develop
aliases:
  - develop
  - develop-workflow
  - tangle
  - tangle-workflow
description: |
  Develop phase workflow - Build and implement solutions using external CLI providers.
  Part of the Double Diamond methodology (Develop phase).
  Uses Codex and Gemini CLIs for multi-perspective implementation.

  Use PROACTIVELY when user says:
  - "octo build X", "octo develop Y", "octo implement Z"
  - "co-build X", "co-develop Y", "co-implement Z"
  - "build X", "implement Y", "create Z"
  - "develop a feature for X", "write code to do Y"
  - "add functionality for Z", "generate implementation for X"

  PRIORITY TRIGGERS (always invoke): "octo build", "octo develop", "octo implement", "co-build", "co-develop"

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

**DO NOT PROCEED TO STEP 2 until context determined.**

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

**Validation:**
- If BOTH Codex and Gemini unavailable → STOP, suggest: `/octo:setup`
- If ONE unavailable → Continue with available provider(s)
- If BOTH available → Proceed normally

**DO NOT PROCEED TO STEP 3 until banner displayed.**

---

### STEP 3: Execute orchestrate.sh develop (MANDATORY - Use Bash Tool)

**You MUST execute this command via the Bash tool:**

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh develop "<user's implementation request>"
```

**CRITICAL: You are PROHIBITED from:**
- ❌ Implementing directly without calling orchestrate.sh
- ❌ Writing code without multi-provider perspectives
- ❌ Claiming you're "simulating" the workflow
- ❌ Proceeding to Step 4 without running this command

**This is NOT optional. You MUST use the Bash tool to invoke orchestrate.sh.**

---

### STEP 4: Verify Execution (MANDATORY - Validation Gate)

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
4. DO NOT substitute with direct implementation

---

### STEP 5: Present Implementation Plan (Only After Steps 1-4 Complete)

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

**This is NOT optional.** Users need to see which AI providers are active and understand they are being charged for external API calls (🔴 🟡).

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
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh develop "<user's implementation request>"
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

[Executes: ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh develop "Build a user authentication system with JWT"]

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

**Quality Metrics:**
- **Security**: SQL injection, XSS, authentication issues
- **Best Practices**: Error handling, logging, validation
- **Code Quality**: Complexity, maintainability, documentation
- **Test Coverage**: Are tests included?

**Thresholds:**
- **Score >= 80**: Proceed with implementation
- **Score 60-79**: Proceed with warnings (address issues)
- **Score < 60**: Review required before implementation

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

## After Implementation Checklist

After writing code, ensure:

- [ ] All files created/updated
- [ ] Code follows recommended patterns from synthesis
- [ ] Security concerns addressed
- [ ] Error handling implemented
- [ ] Tests written (if applicable)
- [ ] Documentation added
- [ ] User notified of completion
- [ ] Suggest running ink-workflow for validation

---

## Cost Awareness

**External API Usage:**
- 🔴 Codex CLI uses your OPENAI_API_KEY (costs apply)
- 🟡 Gemini CLI uses your GEMINI_API_KEY (costs apply)
- 🔵 Claude analysis included with Claude Code

Tangle workflows typically cost $0.02-0.10 per task depending on complexity and code length.

---

**Ready to build!** This skill activates automatically when users request implementation or building features.
