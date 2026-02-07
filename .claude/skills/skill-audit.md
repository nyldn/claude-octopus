---
name: skill-audit
aliases:
  - audit
  - systematic-check
  - comprehensive-audit
description: Systematic codebase auditing with comprehensive checklists
trigger: |
  AUTOMATICALLY ACTIVATE when user requests auditing:
  - "audit and check the entire app"
  - "audit X for Y" or "check for broken features"
  - "process to audit" or "systematic check"
  - "scan for issues" or "find all instances of X"

  DO NOT activate for:
  - Security audits (use skill-security-audit)
  - Code reviews (use skill-code-review)
  - Simple grep/search operations
---

# Systematic Audit Process

## Overview

Comprehensive, methodical auditing to find issues, inconsistencies, and broken features across a codebase.

**Core principle:** Define scope → Create checklist → Execute systematically → Report findings → Prioritize fixes.

---

## When to Use

**Use this skill when user wants to:**
- Audit entire application for issues
- Find all instances of a problem pattern
- Check for broken features systematically
- Comprehensive quality verification
- Identify inconsistencies across codebase

**Do NOT use for:**
- Security vulnerability scanning (use skill-security-audit)
- Code quality review (use skill-code-review)
- Single file searches (use Grep/Glob directly)
- Performance profiling

---

## The Process

### Phase 1: Scope Definition

#### Step 1: Understand Audit Objectives

```markdown
**Audit Objectives:**

What to audit: [app features, code patterns, specific issues]
Why auditing: [what prompted this, what problem are we solving]
Scope: [entire app, specific module, particular feature set]
Depth: [surface-level or deep inspection]
```

#### Step 2: Define Audit Criteria

Use AskUserQuestion if needed:

```markdown
**Audit Focus:**

Which aspects should I audit?
1. Functional - Do features work as expected?
2. Consistency - Are patterns applied uniformly?
3. Completeness - Are implementations finished?
4. Quality - Is code maintainable?
5. User-facing - Does UI/UX work correctly?
6. Integration - Do components work together?
```

#### Step 3: Create Audit Plan

```markdown
**Audit Plan**

**Areas to Cover:**
1. [Area 1: e.g., All form submissions]
2. [Area 2: e.g., All API endpoints]
3. [Area 3: e.g., All button states]
4. [Area 4: e.g., All error handling]

**Methodology:**
- [ ] Identify all instances
- [ ] Test each systematically
- [ ] Document findings
- [ ] Categorize by severity
- [ ] Propose fixes

**Estimated Coverage:** [X components, Y files, Z features]
```

---

### Phase 2: Discovery

#### Step 1: Identify Audit Targets

Use Glob and Grep to find all relevant code:

```markdown
**Finding Audit Targets:**

Searching for: [pattern/feature]
Method: [glob pattern or grep query]

**Found:**
1. [File 1:line]
2. [File 2:line]
3. [File 3:line]
...
N. [File N:line]

Total instances: [N]
```

#### Step 2: Create Audit Checklist

```markdown
**Audit Checklist:**

- [ ] Item 1: [component/feature to check]
  - Location: [file:line]
  - Expected: [what should happen]
  - Test: [how to verify]

- [ ] Item 2: [component/feature to check]
  - Location: [file:line]
  - Expected: [what should happen]
  - Test: [how to verify]

...

Total items to audit: [N]
```

Use TodoWrite to track audit progress.

---

### Phase 3: Systematic Execution

#### Step 1: Execute Audit Checklist

For each item:

```markdown
**Auditing Item [N]/[Total]: [Description]**

**Location:** [file:line]

**Check 1: [Test name]**
- Expected: [what should happen]
- Method: [how to test - code review, runtime check, etc.]
- Result: ✓ Pass / ❌ Fail
- Evidence: [what you observed]

**Check 2: [Test name]**
- Expected: [what should happen]
- Method: [how to test]
- Result: ✓ Pass / ❌ Fail
- Evidence: [what you observed]

**Overall Status:** ✓ Pass / ⚠️ Issues Found / ❌ Broken

**Issues:**
[If any issues, list them here]

---
```

#### Step 2: Track Progress

```
Audit Progress:
✓ [1/50] User login form
✓ [2/50] Password reset form
⚠️ [3/50] Registration form (issues found)
❌ [4/50] Contact form (broken)
⚙️ [5/50] Newsletter signup (in progress)
- [6/50] Survey form
...
```

---

### Phase 4: Analysis & Reporting

#### Step 1: Categorize Findings

```markdown
**Audit Findings Summary**

**Critical Issues (Broken Functionality):**
1. [Issue 1]
   - Location: [file:line]
   - Impact: [what's broken]
   - Severity: Critical

2. [Issue 2]
   - Location: [file:line]
   - Impact: [what's broken]
   - Severity: Critical

**Major Issues (Degraded Functionality):**
1. [Issue 1]
   - Location: [file:line]
   - Impact: [what's wrong]
   - Severity: Major

**Minor Issues (Inconsistencies/Polish):**
1. [Issue 1]
   - Location: [file:line]
   - Impact: [what's inconsistent]
   - Severity: Minor

**Passed Checks:**
- [N] items fully functional
- [List if relevant]
```

#### Step 2: Provide Statistics

```markdown
**Audit Statistics**

Total Items Audited: [N]
✓ Passed: [N] ([X%])
⚠️ Issues Found: [N] ([X%])
❌ Broken: [N] ([X%])

**By Category:**
- Critical: [N]
- Major: [N]
- Minor: [N]

**Coverage:**
- Files reviewed: [N]
- Components tested: [N]
- Code paths verified: [N]
```

---

### Phase 5: Remediation Plan

#### Step 1: Prioritize Issues

```markdown
**Recommended Fix Priority:**

**Phase 1: Critical Fixes (Do First)**
1. [Issue - file:line]
   - Why critical: [reason]
   - Estimated effort: [time]

2. [Issue - file:line]
   - Why critical: [reason]
   - Estimated effort: [time]

**Phase 2: Major Fixes (Do Next)**
1. [Issue - file:line]
   - Impact: [description]
   - Estimated effort: [time]

**Phase 3: Minor Fixes (Nice to Have)**
1. [Issue - file:line]
   - Impact: [description]
   - Estimated effort: [time]

**Total Estimated Effort:** [sum of all fixes]
```

#### Step 2: Offer to Execute Fixes

```markdown
**Next Steps:**

I found [N] issues during the audit.

Would you like me to:
1. Fix all critical issues now (estimated [time])
2. Fix issues one category at a time (critical → major → minor)
3. Let you review findings first, then decide what to fix
4. Create detailed tickets/todos for each issue

What's your preference?
```

---

## Common Patterns

### Pattern 1: Audit Entire App for Broken Features

```
User: "Create a process to audit and check the entire app for things that might be broken"

Implementation:

**Phase 1: Scope**
- Audit all user-facing features
- Check for runtime errors
- Verify expected behavior

**Phase 2: Discovery**
- List all features (from routes, components, docs)
- Create comprehensive checklist

**Phase 3: Execute**
- Test each feature systematically
- Document working vs broken

**Phase 4: Report**
- Critical: Features that crash
- Major: Features that work incorrectly
- Minor: Features with UX issues

**Phase 5: Fix**
- Prioritized remediation plan
```

### Pattern 2: Audit for Specific Pattern

```
User: "Find all instances of direct DOM manipulation and check if they should use React state"

Implementation:

**Phase 1: Scope**
- Audit: Direct DOM manipulation patterns
- Goal: Identify React anti-patterns

**Phase 2: Discovery**
- Grep for: document.querySelector, getElementById, etc.
- Found: [N] instances

**Phase 3: Execute**
- Check each instance:
  - Is there a good reason for direct DOM?
  - Should it use React state instead?
  - Is it causing bugs?

**Phase 4: Report**
- List instances that should migrate to React
- List instances that are fine as-is

**Phase 5: Fix**
- Refactor problematic instances
```

### Pattern 3: Consistency Audit

```
User: "Audit the app for button style consistency"

Implementation:

**Phase 1: Scope**
- Audit: All button elements
- Goal: Ensure consistent styling

**Phase 2: Discovery**
- Find all buttons in codebase
- Identify button component(s)

**Phase 3: Execute**
- Check each button against style guide
- Document inconsistencies

**Phase 4: Report**
- Buttons using correct component: [N]
- Buttons with inconsistent styles: [N]
- Buttons using deprecated patterns: [N]

**Phase 5: Fix**
- Standardize all buttons to design system
```

---

## Integration with Other Skills

### With skill-debug

```
Audit found a broken feature?
→ Use skill-debug to investigate root cause
→ Use systematic debugging to fix
```

### With skill-visual-feedback

```
Audit found UI inconsistencies?
→ Use skill-visual-feedback to fix visual issues
→ Ensure consistency across app
```

### With skill-iterative-loop

```
Large audit with many items?
→ Use skill-iterative-loop to process in batches
→ Loop through sections of the app
```

### With skill-security-audit

```
Audit includes security concerns?
→ Delegate security-specific checks to skill-security-audit
→ Use skill-audit for functional checks
```

---

## Best Practices

### 1. Be Systematic, Not Random

**Good:**
```
Auditing all form submissions:
1. Login form
2. Registration form
3. Password reset form
4. Contact form
5. Newsletter signup
...
(Methodical, complete)
```

**Poor:**
```
Checking some forms:
- Login form
- Maybe that contact thing
- Whatever else I find
(Random, incomplete)
```

### 2. Document Everything

For each audit item, record:
- What was checked
- How it was checked
- Result (pass/fail)
- Evidence (what you observed)

### 3. Use Categories

Group findings into meaningful categories:
- By severity (critical, major, minor)
- By type (functional, UI, consistency, performance)
- By component (forms, navigation, data display)

### 4. Make Findings Actionable

**Good:**
```
Issue: Registration form submit button doesn't work
Location: src/components/RegisterForm.tsx:45
Root cause: onClick handler missing
Fix: Add onClick={handleSubmit}
Effort: 5 minutes
```

**Poor:**
```
Issue: Some button broken somewhere
Fix: Fix it
```

---

## Red Flags - Don't Do This

| Action | Why It's Wrong |
|--------|----------------|
| Skip creating checklist | Will miss things, duplicate work |
| Test randomly without system | Incomplete coverage |
| Not documenting findings | Can't prioritize or fix later |
| Audit without clear criteria | Don't know what "pass" means |
| Fix while auditing | Confuses audit with remediation |
| Ignore patterns | Miss systemic issues |

---

## Audit Templates

### Template 1: Functional Feature Audit

```markdown
**Feature:** [Name]
**Location:** [file:line]

**Tests:**
- [ ] Feature loads without errors
- [ ] Feature responds to user input
- [ ] Feature displays correct data
- [ ] Feature handles errors gracefully
- [ ] Feature works on mobile
- [ ] Feature is accessible

**Result:** ✓ Pass / ⚠️ Issues / ❌ Broken
**Issues:** [if any]
```

### Template 2: Code Pattern Audit

```markdown
**Pattern:** [What to check]
**Instance:** [file:line]

**Checks:**
- [ ] Follows current best practices
- [ ] Consistent with codebase
- [ ] No deprecated APIs used
- [ ] Properly typed/documented
- [ ] No obvious bugs

**Result:** ✓ Good / ⚠️ Needs update / ❌ Problematic
**Notes:** [any observations]
```

### Template 3: UI Consistency Audit

```markdown
**Component:** [Name]
**Location:** [file:line]

**Checks:**
- [ ] Uses design system components
- [ ] Follows spacing guidelines
- [ ] Uses correct colors
- [ ] Typography consistent
- [ ] Responsive design works
- [ ] States handled (hover, active, disabled)

**Result:** ✓ Consistent / ⚠️ Minor issues / ❌ Inconsistent
**Issues:** [if any]
```

---

## Quick Reference

| Audit Type | Discovery Method | Check Method | Output |
|------------|------------------|--------------|--------|
| Functional | List features | Test each | Pass/fail report |
| Pattern | Grep for code | Review each instance | Compliant/non-compliant |
| Consistency | Find all instances | Compare to standard | Consistent/inconsistent |
| Completeness | List requirements | Verify each exists | Complete/incomplete |

---

## The Bottom Line

```
Systematic audit → Complete checklist + Methodical execution + Prioritized findings
Otherwise → Missed issues + Duplicate work + No clear action plan
```

**Define scope. Create checklist. Execute systematically. Report findings. Prioritize fixes.**
