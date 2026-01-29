---
name: skill-code-review
aliases:
  - review
  - code-review
description: |
  Expert code review with comprehensive quality assessment, security analysis, and architecture feedback.
  
  Use PROACTIVELY when user says:
  - "review this code", "code review X", "review my changes"
  - "check this PR", "review this pull request"
  - "what's wrong with this code", "find issues in X"
  - "quality check", "review for best practices"
  
  PRIORITY TRIGGERS: "octo review", "code review", "review this"
  
  DO NOT use for: debugging (use skill-debug), security-only audits (use skill-security-audit),
  quick pre-commit checks (use skill-quick-review).
context: fork
agent: Explore
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - review_output_exists
---

# Code Review Skill

Invokes the code-reviewer persona for thorough code analysis during the `ink` (deliver) phase.

## Usage

```bash
# Via orchestrate.sh
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh spawn code-reviewer "Review this pull request for security issues"

# Via auto-routing (detects review intent)
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh auto "review the authentication implementation"
```

## Capabilities

- AI-powered code quality analysis
- Security vulnerability detection
- Performance optimization suggestions
- Architecture and design pattern review
- Best practices enforcement

## Persona Reference

This skill wraps the `code-reviewer` persona defined in:
- `agents/personas/code-reviewer.md`
- CLI: `codex-review`
- Model: `gpt-5.2-codex`
- Phases: `ink`

## Example Prompts

```
"Review this PR for OWASP Top 10 vulnerabilities"
"Analyze the error handling in src/api/"
"Check for memory leaks in the connection pool"
"Review the test coverage for the auth module"
```

---

## Implementation Completeness Verification

After the code-reviewer persona completes, run stub detection to verify implementation completeness.

### Stub Detection Process

**Step 1: Get changed files**

```bash
# Get files changed in the commit/PR
if [ -n "$COMMIT_RANGE" ]; then
    changed_files=$(git diff --name-only "$COMMIT_RANGE")
else
    changed_files=$(git diff --name-only HEAD~1..HEAD)
fi

# Filter for source code files
source_files=$(echo "$changed_files" | grep -E "\.(ts|tsx|js|jsx|py|go)$")
```

**Step 2: Check for stub patterns**

For each changed file, check for common stub indicators:

```bash
for file in $source_files; do
    echo "Checking $file for stubs..."

    # Check 1: Comment-based stubs
    stub_count=$(grep -E "(TODO|FIXME|PLACEHOLDER|XXX)" "$file" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$stub_count" -gt 0 ]; then
        echo "⚠️  WARNING: Found $stub_count stub indicators in $file"
        grep -n -E "(TODO|FIXME|PLACEHOLDER)" "$file" | head -3
    fi

    # Check 2: Empty function bodies
    empty_functions=$(grep -E "function.*\{\s*\}|const.*=>.*\{\s*\}" "$file" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$empty_functions" -gt 0 ]; then
        echo "❌ ERROR: Found $empty_functions empty functions in $file"
        echo "   Empty functions must be implemented before merge"
    fi

    # Check 3: Return null/undefined
    null_returns=$(grep -E "return (null|undefined);" "$file" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$null_returns" -gt 0 ]; then
        echo "⚠️  WARNING: Found $null_returns null/undefined returns in $file"
        echo "   Verify these are intentional, not stubs"
    fi

    # Check 4: Substantive content check
    substantive_lines=$(grep -vE "^\s*(//|/\*|\*|import|export|$)" "$file" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$file" == *.tsx ]] && [ "$substantive_lines" -lt 10 ]; then
        echo "⚠️  WARNING: Component $file only has $substantive_lines substantive lines"
        echo "   Components should typically be >10 lines"
    fi

    # Check 5: Mock/test data in production
    mock_data=$(grep -E "const.*(mock|test|dummy|fake).*=" "$file" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$mock_data" -gt 0 ]; then
        echo "⚠️  WARNING: Found $mock_data references to mock/test data in $file"
        echo "   Ensure these are not placeholders for production code"
    fi
done
```

**Step 3: Add findings to review synthesis**

Include stub detection results in the review output:

```markdown
## Implementation Completeness

**Stub Detection Results:**

✅ **Fully Implemented Files:**
- src/components/UserProfile.tsx (42 substantive lines)
- src/api/users.ts (67 substantive lines)

⚠️  **Files with Warnings:**
- src/components/Dashboard.tsx
  - 3 TODO comments (non-blocking)
  - Consider addressing before release

❌ **Files Requiring Implementation:**
- src/utils/analytics.ts
  - 2 empty functions detected (BLOCKING)
  - Must implement before merge

**Verification Levels:**
- Level 1 (Exists): 5/5 files ✅
- Level 2 (Substantive): 3/5 files ⚠️
- Level 3 (Wired): 4/5 files ✅
- Level 4 (Functional): Tests pending

**Recommendation:**
- Fix empty functions in analytics.ts before merge
- Address TODO comments in Dashboard.tsx in follow-up PR
- All other files meet implementation standards
```

### Stub Detection Reference

See `.claude/references/stub-detection.md` for comprehensive patterns and detection strategies.

### When to Block Merge

**BLOCKING Issues (must fix):**
- ❌ Empty function bodies
- ❌ Mock data in production code paths
- ❌ Components not imported/wired anywhere
- ❌ API endpoints returning empty objects

**NON-BLOCKING Issues (note in review):**
- ⚠️ TODO/FIXME comments (create follow-up tickets)
- ⚠️ Null returns (if intentional)
- ⚠️ Low line count (if appropriate for the component)
