---
name: skill-code-review
version: 1.0.0
description: "Expert multi-AI code review with quality and security analysis"
---

# Code Review Skill

## MANDATORY COMPLIANCE — DO NOT SKIP

**When this skill is invoked, you MUST execute the multi-LLM review pipeline. You are PROHIBITED from:**
- Doing a direct single-model code review without multi-provider synthesis
- Deciding the scope is "too broad" and narrowing it without asking the user
- Skipping the provider check or structured review phases
- Substituting two background Sonnet agents for the full multi-provider pipeline
- Rationalizing "a focused audit would be more effective" — the user wants multi-LLM perspectives

---

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-LLM Code Review`

Invokes the code-reviewer persona for thorough code analysis during the `ink` (deliver) phase.

## Quick Mode

For fast sanity checks (staged changes, small PRs), skip the full review pipeline and run just two phases:

```bash
# Quick: grasp (consensus on scope) → tangle (parallel review)
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh grasp "[review request]"
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh tangle "[synthesized scope]"
```

Use quick mode when user says "check this PR", "quick review", "sanity check my changes", or for pre-commit checks. Use the full review for PRs with security/architecture impact.

## Usage

```bash
# Via orchestrate.sh
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh spawn code-reviewer "Review this pull request for security issues"

# Via auto-routing (detects review intent)
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "review the authentication implementation"
```

## Capabilities

- AI-powered code quality analysis
- Security vulnerability detection
- Performance optimization suggestions
- Architecture and design pattern review
- TDD compliance and test-first evidence review
- Autonomous code generation risk detection
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

## Pre-Review: Scope Drift Check

Before starting the code review pipeline, compare the diff against stated intent (TODOS.md, PR body, commit messages) to surface scope creep and missing requirements. Display findings as CLEAN / DRIFT DETECTED / REQUIREMENTS MISSING.

**This is informational — it never blocks the review.** Include drift findings in the final review synthesis if drift was detected.

---

## Autonomous Implementation Review

When the review context indicates `AI-assisted`, `Autonomous / Dark Factory`, or unclear provenance, raise the rigor bar. Do not treat generated code as trustworthy just because it is polished.

### TDD Evidence

Check for concrete signs that the change followed red-green-refactor rather than test-after implementation:

- Compare the diff and recent history when available to see whether tests were added before or alongside production changes.
- Prefer behavior-defining tests over snapshot-only or mock-heavy tests that merely restate the implementation.
- Verify the production code looks like the minimum needed to satisfy the tests, rather than a speculative abstraction with unused options.
- If evidence is missing, mark TDD compliance as unknown and do not assume TDD happened.

### Autonomous Codegen Risk Patterns

Elevate or add findings when you see patterns common in high-autonomy output:

- Option-heavy APIs or abstractions not justified by tests or current requirements
- Placeholder logic, TODO/FIXME-driven control flow, or dead branches that appear "future ready"
- Mock, fake, or dummy behavior leaking into production paths
- Unwired components, unused helpers, or code that exists without an execution path
- Silent failure handling, broad catch blocks, missing logs, or weak operational visibility
- Missing rollback notes, migration guards, or release-safety checks for risky changes

### Review Output Addendum

Add a short section to the review synthesis when autonomy or TDD is in scope:

```markdown
## TDD / Autonomy Assessment

- Provenance: Human-authored | AI-assisted | Autonomous / Dark Factory | Unknown
- TDD evidence: Confirmed | Partial | Unknown
- Autonomous risk signals: None | Minor | Significant
- Recommendation: Ship | Fix before merge | Re-run with /octo:tdd or tighter supervision
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

---

## Post Review to PR (v8.44.0)

After generating the review synthesis, check if the current branch has an open PR and offer to post findings as a PR comment.

### Step 1: Detect Open PR

```bash
# Check if we're on a branch with an open PR
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
PR_NUM=""

if [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
    if command -v gh &>/dev/null; then
        PR_NUM=$(gh pr list --head "$CURRENT_BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
    fi
fi
```

### Step 2: Post Review Comment

If an open PR exists, post the review findings as a PR comment:

```bash
if [[ -n "$PR_NUM" ]]; then
    echo "Found open PR #${PR_NUM} on branch ${CURRENT_BRANCH}"

    # Build the review comment body from synthesis
    REVIEW_BODY="## Code Review — Claude Octopus

${REVIEW_SYNTHESIS}

---
*Review generated by Claude Octopus (/octo:review)*
*Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude*"

    # Post as PR comment
    gh pr comment "$PR_NUM" --body "$REVIEW_BODY"
    echo "Review posted to PR #${PR_NUM}"

    # Update agent registry if this agent is tracked
    REGISTRY="${HOME}/.claude-octopus/plugin/scripts/agent-registry.sh"
    if [[ -x "$REGISTRY" ]]; then
        AGENT_ID=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        "$REGISTRY" update "$AGENT_ID" --pr "$PR_NUM" 2>/dev/null || true
    fi
fi
```

**If no PR exists:** Skip posting, present review in terminal only.
**If `gh` CLI not available:** Skip posting, suggest user install GitHub CLI.

### When to Auto-Post vs Ask

- **Auto-post:** When invoked as part of `/octo:deliver`, `/octo:factory`, or `/octo:embrace` (automated workflows)
- **Ask first:** When invoked standalone via `/octo:review` — use AskUserQuestion:
  ```
  "PR #N found. Post review findings as a PR comment?"
  Options: "Yes, post to PR", "No, terminal only"
  ```
