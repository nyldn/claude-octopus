---
name: flow-deliver
aliases:
  - deliver
  - deliver-workflow
  - ink
  - ink-workflow
description: |
  Deliver phase workflow - Review, validate, and test using external CLI providers.
  Part of the Double Diamond methodology (Deliver phase).
  Uses Codex and Gemini CLIs for multi-perspective validation.
  
  Use PROACTIVELY when user says:
  - "octo review X", "octo validate Y", "octo deliver Z"
  - "co-review X", "co-validate Y", "co-deliver Z"
  - "review X", "validate Y", "test Z"
  - "check if X works correctly", "verify the implementation of Y"
  - "find issues in Z", "quality check for X"
  - "ensure Y meets requirements", "audit X for security"
  
  PRIORITY TRIGGERS (always invoke): "octo review", "octo validate", "octo deliver", "co-review", "co-deliver"
  
  DO NOT use for: implementation (use flow-develop), research (use flow-discover),
  requirement definition (use flow-define), or simple code reading.
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

# Deliver Workflow - Deliver Phase ✅

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
- **Code Review**: "Review the authentication implementation"
- **Quality Validation**: "Validate the API endpoints"
- **Security Audit**: "Check for security vulnerabilities in X"
- **Implementation Verification**: "Verify the caching layer works correctly"
- **Pre-Deployment Check**: "Ensure the feature is ready to ship"
- **Bug Verification**: "Confirm the bug fix resolves the issue"

**Don't use deliver for:**
- Building implementations (use tangle-workflow)
- Research and exploration (use probe-workflow)
- Requirement definition (use grasp-workflow)
- Simple code reading (use Read tool)

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
./scripts/orchestrate.sh deliver "<user's validation request>"
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

When this skill activates:

1. **Confirm the validation task**
   ```
   I'll review "<task>" using multiple AI perspectives.

   🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider validation
   ✅ Deliver Phase: Validating implementation
   ```

2. **Execute ink workflow**
   ```bash
   ./scripts/orchestrate.sh deliver "<user's validation request>"
   ```

3. **Monitor execution and quality gates**
   - Watch for provider responses
   - Check quality gate scores
   - Note critical issues or blockers

4. **Read validation results**
   ```bash
   # Find the latest validation file
   VALIDATION_FILE=$(ls -t ~/.claude-octopus/results/${CLAUDE_CODE_SESSION}/ink-validation-*.md 2>/dev/null | head -n1)

   # Read validation report
   cat "$VALIDATION_FILE"
   ```

5. **Present validation report in chat**
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

[Executes: ./scripts/orchestrate.sh deliver "Review authentication implementation in src/auth/"]

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

**Ready to validate!** This skill activates automatically when users request code review, validation, or quality checks.
