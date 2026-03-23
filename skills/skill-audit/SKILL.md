---
name: skill-audit
version: 1.0.0
description: "Systematic codebase audit for quality, consistency, and broken patterns with checklist-driven execution and prioritized remediation. Use when: user says 'audit the app', 'check for broken features', 'audit X for Y', 'find all instances of', or needs pre-release verification or tech debt review."
---

# Systematic Audit Process

**Core principle:** Define scope, create checklist, execute systematically, report findings by severity, prioritize fixes.

## When to Use

**Activate when user wants to:** audit entire application, find problem pattern instances, check for broken features, verify quality/consistency across codebase.

**Do NOT use for:** security scanning (use skill-security-audit), code review (use skill-code-review), single file searches (use Grep/Glob), performance profiling.

---

## The Process

### Phase 1: Scope Definition

Define: what to audit, why, scope (entire app vs module), depth, and audit criteria (functional, consistency, completeness, quality, UI/UX, integration). Create audit plan with areas to cover and estimated coverage.

### Phase 2: Discovery

Use Glob and Grep to find all audit targets. Create a checklist with location, expected behavior, and test method for each item.

### Phase 3: Systematic Execution

For each checklist item: run checks, record pass/fail with evidence, track progress. Report overall status per item.

### Phase 4: Analysis & Reporting

Categorize findings by severity:
- **Critical**: Broken functionality (location, impact, severity)
- **Major**: Degraded functionality
- **Minor**: Inconsistencies/polish

Provide statistics: total audited, pass/fail percentages, coverage metrics.

### Phase 5: Remediation Plan

Prioritize fixes (critical first, then major, then minor) with estimated effort per issue. Offer to: fix all critical issues now, fix by category, let user review first, or create tickets.

---

## Integration with Other Skills

- **skill-debug**: Investigate root causes of broken features found during audit
- **skill-visual-feedback**: Fix UI inconsistencies
- **skill-iterative-loop**: Process large audits in batches
- **skill-security-audit**: Delegate security-specific checks

---

## Best Practices

1. **Be systematic**: Enumerate all targets methodically, never random spot-checks
2. **Document everything**: What was checked, how, result, evidence
3. **Categorize findings**: By severity (critical/major/minor) and type (functional/UI/consistency)
4. **Make findings actionable**: Include file:line, root cause, specific fix, effort estimate

---

## Quick Reference

| Audit Type | Discovery Method | Check Method | Output |
|------------|------------------|--------------|--------|
| Functional | List features | Test each | Pass/fail report |
| Pattern | Grep for code | Review each instance | Compliant/non-compliant |
| Consistency | Find all instances | Compare to standard | Consistent/inconsistent |
| Completeness | List requirements | Verify each exists | Complete/incomplete |
