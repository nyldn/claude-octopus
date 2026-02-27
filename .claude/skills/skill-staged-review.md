---
name: skill-staged-review
aliases:
  - staged-review
  - two-stage-review
description: "Two-stage spec-then-quality review pipeline"
trigger: |
  Use when completing a major feature, preparing a PR, or when user says
  "staged review", "full review", "review against spec", or "two-stage review".
  Do NOT use for quick code checks — use skill-code-review instead.
execution_mode: enforced
validation_gates:
  - stage1_complete
  - stage2_complete
---

# Two-Stage Review Pipeline

Separates **spec compliance** (did you build the right thing?) from **code quality**
(did you build it right?). Stage 1 must pass before Stage 2 runs.

---

## Stage 1: Spec Compliance

Validates the implementation against the intent contract.

### Step 1: Load Intent Contract

```bash
INTENT_FILE=".claude/session-intent.md"
if [[ -f "$INTENT_FILE" ]]; then
  echo "Intent contract found: $INTENT_FILE"
  cat "$INTENT_FILE"
else
  echo "WARNING: No intent contract found at $INTENT_FILE"
  echo "Skipping Stage 1 — proceeding to Stage 2 (code quality) only."
fi
```

**If no intent contract exists:** Warn the user and skip to Stage 2. Do NOT fabricate
success criteria — the contract must exist from a prior workflow.

### Step 2: Validate Success Criteria

For each success criterion in the intent contract:

1. **Read the criterion** from the `## Success Criteria` section
2. **Find evidence** in the codebase that the criterion is met
3. **Mark status:**
   - `[PASS]` — Evidence confirms criterion is met
   - `[FAIL]` — Evidence shows criterion is NOT met
   - `[PARTIAL]` — Partially met, gaps identified

Present results:

```markdown
## Stage 1: Spec Compliance

### Success Criteria Check

#### Good Enough Criteria
- [PASS] Criterion 1: <how it was met>
- [FAIL] Criterion 2: <why not met, what's missing>

#### Exceptional Criteria
- [PARTIAL] Criterion 1: <what's done, what's remaining>
```

### Step 3: Validate Boundaries

For each boundary in the intent contract:

1. **Read the boundary** from the `## Boundaries` section
2. **Check for violations** in the implementation
3. **Mark status:**
   - `[RESPECTED]` — No violations found
   - `[VIOLATED]` — Implementation crosses the boundary

```markdown
### Boundary Check
- [RESPECTED] Boundary 1: <confirmation>
- [VIOLATED] Boundary 2: <what violated it>
```

### Step 4: Stage 1 Gate

| Result | Action |
|--------|--------|
| All criteria PASS + all boundaries RESPECTED | Proceed to Stage 2 |
| Any criterion FAIL | Report failures. Ask user: fix now or proceed anyway? |
| Any boundary VIOLATED | Report violations. Ask user: fix now or proceed anyway? |

**If user chooses to fix:** Stop review, list specific fixes needed.
**If user chooses to proceed:** Note the overrides and continue to Stage 2.

---

## Stage 2: Code Quality

Runs stub detection and full code quality review.

### Step 1: Stub Detection

Run 5 checks on all changed files:

```bash
# Get changed files
if git diff --cached --name-only 2>/dev/null | head -1 > /dev/null; then
  changed_files=$(git diff --cached --name-only)
elif git diff --name-only HEAD~1..HEAD 2>/dev/null | head -1 > /dev/null; then
  changed_files=$(git diff --name-only HEAD~1..HEAD)
else
  changed_files=$(git diff --name-only)
fi

# Filter source files
source_files=$(echo "$changed_files" | grep -E "\.(ts|tsx|js|jsx|py|go|rs|sh)$" || true)

STUB_ISSUES=0

for file in $source_files; do
  [[ -f "$file" ]] || continue

  # Check 1: TODO/FIXME/PLACEHOLDER markers
  todo_count=$(grep -cE "(TODO|FIXME|PLACEHOLDER|XXX)" "$file" 2>/dev/null || echo "0")
  if [[ "$todo_count" -gt 0 ]]; then
    echo "WARNING: $file has $todo_count TODO/FIXME markers"
    STUB_ISSUES=$((STUB_ISSUES + 1))
  fi

  # Check 2: Empty function bodies
  empty_fn=$(grep -cE "function.*\{\s*\}|=>\s*\{\s*\}" "$file" 2>/dev/null || echo "0")
  if [[ "$empty_fn" -gt 0 ]]; then
    echo "ERROR: $file has $empty_fn empty functions"
    STUB_ISSUES=$((STUB_ISSUES + 1))
  fi

  # Check 3: Suspicious null/undefined returns
  null_ret=$(grep -cE "return (null|undefined);" "$file" 2>/dev/null || echo "0")
  if [[ "$null_ret" -gt 0 ]]; then
    echo "WARNING: $file has $null_ret null/undefined returns — verify intentional"
    STUB_ISSUES=$((STUB_ISSUES + 1))
  fi

  # Check 4: Substantive line count
  subst_lines=$(grep -cvE "^\s*(//|/\*|\*|#|import|export|$)" "$file" 2>/dev/null || echo "0")
  if [[ "$subst_lines" -lt 5 ]]; then
    echo "WARNING: $file has only $subst_lines substantive lines"
    STUB_ISSUES=$((STUB_ISSUES + 1))
  fi

  # Check 5: Mock/test data in production code
  mock_count=$(grep -cE "const.*(mock|test|dummy|fake).*=" "$file" 2>/dev/null || echo "0")
  if [[ "$mock_count" -gt 0 ]]; then
    echo "WARNING: $file has $mock_count mock/test data references"
    STUB_ISSUES=$((STUB_ISSUES + 1))
  fi
done

echo "Stub detection complete: $STUB_ISSUES issues found"
```

### Step 2: Full Quality Review

After stub detection, perform a comprehensive code quality review:

1. **Architecture alignment** — Does the code follow project patterns?
2. **Error handling** — Are errors caught and handled appropriately?
3. **Security** — Any OWASP Top 10 issues?
4. **Performance** — Any obvious bottlenecks or N+1 queries?
5. **Readability** — Clear naming, reasonable complexity?
6. **Test coverage** — Are new behaviors tested?

### Step 3: Present Stage 2 Results

```markdown
## Stage 2: Code Quality

### Stub Detection
- Files scanned: N
- Issues found: N
- [Details of each issue]

### Quality Review
- Architecture: [PASS/WARN/FAIL]
- Error Handling: [PASS/WARN/FAIL]
- Security: [PASS/WARN/FAIL]
- Performance: [PASS/WARN/FAIL]
- Readability: [PASS/WARN/FAIL]
- Test Coverage: [PASS/WARN/FAIL]

### Blocking Issues
[List any issues that must be fixed before merge]

### Recommendations
[Non-blocking suggestions for improvement]
```

---

## Combined Report

After both stages complete, present the unified report:

```markdown
## Staged Review — Complete

### Stage 1: Spec Compliance
- Success Criteria: N/N passed
- Boundaries: N/N respected
- Verdict: [PASS/FAIL]

### Stage 2: Code Quality
- Stub Detection: N issues
- Quality Score: [HIGH/MEDIUM/LOW]
- Blocking Issues: N
- Verdict: [PASS/FAIL]

### Overall Verdict: [PASS/FAIL]

[If FAIL: list specific items that must be addressed]
[If PASS: ready for merge/ship]
```

---

## When to Use Each Review Type

| Review Type | When | What It Checks |
|-------------|------|----------------|
| **skill-code-review** | Quick PR review | Code quality only |
| **skill-staged-review** | Major feature completion | Spec compliance + code quality |
| **skill-verify** | Before any completion claim | Evidence of passing |

---

## Error Handling

| Error | Resolution |
|-------|------------|
| No intent contract | Skip Stage 1, warn user, run Stage 2 only |
| No changed files | Report nothing to review |
| Git not available | Use file listing instead of git diff |
| Stage 1 failures | Ask user: fix or override |
| Stage 2 blocking issues | Must fix before merge |

---

## The Bottom Line

```
Staged Review = Spec Compliance (Stage 1) + Code Quality (Stage 2)
Stage 1 gates Stage 2. Both must pass for overall PASS.
```

**Build the right thing, then build it right.**
