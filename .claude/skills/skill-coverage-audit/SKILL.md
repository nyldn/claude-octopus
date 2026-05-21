---
name: skill-coverage-audit
paths:
  - "**/*.test.*"
  - "**/*.spec.*"
  - "**/coverage/**"
aliases:
  - coverage-audit
  - test-coverage
description: "Trace codepaths in diffs, map against tests, auto-generate missing coverage — use before shipping PRs"
trigger: |
  AUTOMATICALLY ACTIVATE when user requests coverage analysis:
  - "check test coverage" or "coverage audit"
  - "what's not tested" or "find untested code"
  - "generate tests for gaps"

  DO NOT activate for:
  - General code audits (use skill-audit)
  - Code review without coverage focus (use skill-code-review)
  - TDD workflow (use skill-tdd)
---

# Test Coverage Audit

## Overview

Trace every codepath in a diff, map each path against existing tests, visualize coverage gaps, and auto-generate tests for uncovered paths.

**Core principle:** Trace codepaths in changed files -> Map against existing tests -> Score coverage quality -> Generate tests for gaps -> Report before/after counts.

---

## Caps and Limits

These hard limits prevent runaway analysis:

- **30 code paths max** per audit. If a diff yields more than 30, prioritize by complexity and risk (error paths, security-sensitive branches, public API surfaces first).
- **20 tests generated max** per audit. Focus on highest-impact gaps first.
- **2-minute per-test exploration cap.** If understanding a single test path takes longer than 2 minutes, mark it as "needs manual review" and move on.

---

## Phase 1: Codepath Tracing

### Step 1: Identify Changed Files

Determine the diff scope. Use the most relevant source:

```bash
# PR diff
git diff --name-only main...HEAD

# Staged changes
git diff --name-only --cached

# Last commit
git diff --name-only HEAD~1..HEAD
```

Filter to source code files only (exclude configs, docs, generated files).

### Step 2: Trace Data Flow Through Every Branch

For each changed file, you MUST trace:

1. **Conditionals** -- Every `if/else`, `switch/case`, ternary, and pattern match. Each branch is a separate codepath.
2. **Error paths** -- Every `catch`, `throw`, error return, validation failure, and early return with error. WHY: Error paths are the most common source of untested bugs.
3. **Function calls** -- Every function invoked from changed code. Trace one level deep into callees to identify integration boundaries.
4. **Loop boundaries** -- Empty collection, single item, and multi-item paths through loops.
5. **Guard clauses** -- Every early return, null check, and permission gate.

### Step 3: Build the Codepath Inventory

Produce a structured inventory:

```markdown
## Codepath Inventory: [filename]

| # | Path Description | Type | Risk |
|---|-----------------|------|------|
| 1 | validateUser() happy path | conditional | low |
| 2 | validateUser() missing email | error | medium |
| 3 | validateUser() invalid format | error | medium |
| 4 | processOrder() empty cart guard | guard | high |
| 5 | processOrder() payment timeout | error | high |
| 6 | processOrder() success | conditional | low |
```

**Type categories:** `conditional`, `error`, `guard`, `loop-boundary`, `integration`, `async`

**Risk assessment:** `high` = user-facing failure or data loss, `medium` = degraded behavior, `low` = cosmetic or logging

---

## Phase 2: Test Mapping and Quality Scoring

### Step 1: Search for Existing Tests

For each file in the diff, search the test directory for related tests:

```bash
# Find test files that reference the changed file or its exports
# Search by filename pattern
find tests/ -name "*[changed_file_stem]*" -type f

# Search by import/require of the changed module
grep -rl "import.*from.*[module_name]" tests/
grep -rl "require.*[module_name]" tests/

# Search by function name references
grep -rl "[function_name]" tests/
```

### Step 2: Score Test Quality

For each codepath, assess existing test coverage with this rubric:

| Rating | Meaning | Criteria |
|--------|---------|----------|
| ★★★ | Behavior + edge cases tested | Tests assert behavior AND cover boundary conditions, error cases, and edge inputs |
| ★★ | Happy path tested | Tests cover the success path but miss error branches or edge cases |
| ★ | Smoke test only | Test exists but only checks the function runs without error (no meaningful assertions) |
| ☆ | No test found | No test references this codepath at all |

### Step 3: Produce Coverage Map

Map each codepath to its test coverage:

```markdown
## Coverage Map: [filename]

| # | Codepath | Test File | Rating | Notes |
|---|----------|-----------|--------|-------|
| 1 | validateUser() happy path | test-user.sh:42 | ★★★ | Asserts valid + invalid inputs |
| 2 | validateUser() missing email | test-user.sh:58 | ★★ | Tests missing, not malformed |
| 3 | validateUser() invalid format | -- | ☆ | No test for format validation |
| 4 | processOrder() empty cart guard | -- | ☆ | Guard clause untested |
| 5 | processOrder() payment timeout | test-orders.sh:30 | ★ | Checks no crash, no assertions |
| 6 | processOrder() success | test-orders.sh:15 | ★★★ | Full integration test |
```

---

## Phase 3: Coverage Diagram

After completing the map, produce an ASCII coverage summary. This is the primary output artifact.

```
COVERAGE: 5/12 paths tested (42%)
  Code paths: 3/5 (60%)
  User flows: 2/7 (29%)
GAPS: 7 paths need tests
```

Break down by category:

```
BY TYPE:
  conditional:  3/4 tested (75%)  ████████░░
  error:        1/5 tested (20%)  ██░░░░░░░░
  guard:        0/2 tested  (0%)  ░░░░░░░░░░
  integration:  1/1 tested (100%) ██████████

BY RISK:
  high:    1/3 tested (33%)  ███░░░░░░░
  medium:  2/5 tested (40%)  ████░░░░░░
  low:     2/4 tested (50%)  █████░░░░░
```

Use full block for covered and light shade for uncovered. 10-character bar. Always show exact fractions and percentages.

---

## Phase 4: Auto-Generate Tests

### Step 1: Detect Project Test Conventions

Before generating any tests, you MUST detect the project's testing patterns:

```markdown
**Detected Test Conventions:**
- Framework: [jest/vitest/pytest/bash/go test/etc.]
- Location: [tests/ | __tests__/ | src/**/*.test.* | etc.]
- Naming: [test-*.sh | *.test.ts | *_test.go | etc.]
- Style: [BDD describe/it | xUnit | TAP | custom]
- Helpers: [test-utils.ts | conftest.py | helpers/ | etc.]
- Assertion library: [built-in | chai | assert | etc.]
```

### Step 2: Generate Tests for Uncovered Paths

For each no-test and smoke-only codepath, generate a test that:

1. **Follows project naming conventions** -- same directory structure, same file naming pattern
2. **Uses existing test helpers** -- import from the same test utilities the project already uses
3. **Tests behavior, not implementation** -- assert observable outcomes, not internal state
4. **Covers the specific gap** -- targets the exact branch or error path identified in Phase 1
5. **Includes edge cases** -- aim for full coverage on each generated test

### Step 3: Present Generated Tests

For each generated test, show:

```markdown
### Generated: test for [codepath description]
**Covers:** Codepath #N from [filename]
**Raises coverage:** from no-test to full coverage

[test code block]
```

### Step 4: Report Before/After

After generating all tests, show the coverage change:

```
BEFORE: 5/12 paths tested (42%)
AFTER:  11/12 paths tested (92%)
  New tests generated: 6
  Remaining gaps: 1 (manual review needed)
```

---

## Integration with Other Skills

### With flow-deliver / skill-code-review

Coverage audit runs as a complement to code review. When invoked during deliver phase:
1. Code review assesses quality and correctness
2. Coverage audit assesses test completeness
3. Both feed into the ship/no-ship decision

### With skill-tdd

If coverage audit finds gaps in new code, recommend the user adopt TDD for the next iteration. Coverage audit fixes existing gaps; TDD prevents future ones.

### With skill-verification-gate

After generating tests, use skill-verification-gate to run the test suite and confirm the new tests pass.

---

## Red Flags -- Do Not Do This

| Action | Why It Is Wrong |
|--------|-----------------|
| Count lines instead of paths | Line coverage misses branch coverage entirely |
| Generate tests without checking conventions | Tests that do not match project style will be rejected |
| Test implementation details | Brittle tests that break on refactoring |
| Skip error paths | Error paths are where most bugs live |
| Exceed the 30-path cap | Analysis becomes unfocused and slow |
| Generate more than 20 tests | Diminishing returns; focus on highest impact |
| Spend more than 2 min on one path | Mark as needs-manual-review and move on |

---

## Quick Reference

```
1. TRACE   -> Identify all codepaths in the diff (max 30)
2. MAP     -> Find existing tests for each path
3. SCORE   -> Rate coverage quality (no-test / smoke / happy-path / full)
4. DIAGRAM -> ASCII coverage visualization
5. GENERATE -> Auto-create tests for gaps (max 20)
6. REPORT  -> Before/after test counts
```
