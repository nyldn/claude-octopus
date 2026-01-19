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

Providers:
🔴 Codex CLI - Code generation and patterns
🟡 Gemini CLI - Alternative approaches
🔵 Claude - Integration and quality gates
```

**For Knowledge Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
🛠️ [Knowledge] Develop Phase: [Brief description of deliverable]

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
./scripts/orchestrate.sh develop "<user's implementation request>"
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

When this skill activates:

1. **Confirm the implementation task**
   ```
   I'll implement "<task>" using multiple AI perspectives.

   🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider implementation mode
   🛠️ Develop Phase: Generating solutions
   ```

2. **Execute tangle workflow**
   ```bash
   ./scripts/orchestrate.sh develop "<user's implementation request>"
   ```

3. **Monitor execution and quality gates**
   - Watch for provider responses
   - Check quality gate results
   - Note any security or quality warnings

4. **Read synthesis results**
   ```bash
   # Find the latest synthesis file
   SYNTHESIS_FILE=$(ls -t ~/.claude-octopus/results/${CLAUDE_CODE_SESSION}/tangle-synthesis-*.md 2>/dev/null | head -n1)

   # Read all perspectives
   cat "$SYNTHESIS_FILE"
   ```

5. **Present implementation plan in chat**
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

[Executes: ./scripts/orchestrate.sh develop "Build a user authentication system with JWT"]

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
