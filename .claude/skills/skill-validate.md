---
name: validate
description: Multi-AI validation combining debate, quality scoring, and issue extraction
version: 1.0.0
category: workflow
tags: [validation, quality-assurance, debate, security, testing]
created: 2025-02-03
updated: 2025-02-03
execution_mode: enforced
pre_execution_contract:
  - interactive_questions_answered
  - visual_indicators_displayed
validation_gates:
  - debate_completed
  - quality_scored
  - issues_extracted
  - validation_report_generated
---

# Validation Workflow

Comprehensive validation combining multi-AI debate, 4-dimensional quality scoring, and automated issue extraction. Provides objective quality assessment with actionable recommendations.

## Overview

The validation workflow uses three AI perspectives (Codex, Gemini, Claude) to evaluate code quality, security, best practices, and completeness. It generates a detailed validation report with scores, identified issues, and recommendations.

**Pass Threshold**: 75/100

## Usage

```bash
# Validate specific files
/octo:validate src/auth.ts

# Validate directory
/octo:validate src/components/

# Validate with focus area
/octo:validate api/ --focus security

# Validate against reference
/octo:validate src/ --reference extraction-results/
```

## Workflow Steps

### Step 1: Scope Analysis
Interactive questions to understand validation context and priorities.

### Step 2: Multi-AI Debate
Single round debate with validation-specific focus from each AI provider.

### Step 3: Quality Scoring
4-dimensional scoring across key quality metrics (75% threshold to pass).

### Step 4: Issue Extraction
Automated extraction and categorization of issues from debate outputs.

### Step 5: Validation Report
Comprehensive report with scores, issues, AI perspectives, and recommendations.

---

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:validate <target>`, you MUST follow these steps sequentially. Each step is BLOCKING - you CANNOT skip or simulate any step.

### 🛡️ STEP 1: Scope Analysis (BLOCKING)

**You MUST use AskUserQuestion tool to gather validation context:**

```yaml
Question 1:
  question: "What validation priorities should I focus on?"
  header: "Priorities"
  multiSelect: true
  options:
    - label: "Security (vulnerabilities, auth, data protection)"
      description: "OWASP top 10, security best practices, authentication/authorization issues"
    - label: "Code Quality (maintainability, readability, patterns)"
      description: "Clean code principles, DRY, SOLID, design patterns, technical debt"
    - label: "Best Practices (framework conventions, ecosystem standards)"
      description: "Language/framework idioms, community standards, linting rules"
    - label: "Performance (optimization, scalability, efficiency)"
      description: "Performance bottlenecks, inefficient algorithms, resource usage"

Question 2:
  question: "What triggered this validation?"
  header: "Trigger"
  multiSelect: false
  options:
    - label: "Pre-commit (quick validation before committing)"
      description: "Fast validation focused on critical issues and linting"
    - label: "Pre-deployment (thorough validation before production)"
      description: "Comprehensive validation including security and performance"
    - label: "Security audit (deep security review)"
      description: "Intensive security-focused analysis with threat modeling"
    - label: "General review (periodic code health check)"
      description: "Balanced validation across all dimensions"
```

**Validation Gate**: User must answer both questions before proceeding.

---

### 🛡️ STEP 2: Multi-AI Debate (BLOCKING)

**You MUST display visual indicators:**

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Validation Workflow
🛡️ Target: <what's being validated>

Validation Layers:
🔴 Codex CLI - Technical quality analysis
🟡 Gemini CLI - Ecosystem best practices
🔵 Claude - Security and integration review
```

**You MUST execute orchestrate.sh with debate mode:**

Use the Bash tool to execute:
```bash
cd "${CLAUDE_PLUGIN_ROOT}"
./scripts/orchestrate.sh debate \
  --topic "Validation of <target>" \
  --rounds 1 \
  --focus "<user's selected priorities>" \
  --context "<validation trigger>" \
  --mode validation
```

**Debate Focus by Priority:**

- **Security**: Vulnerabilities, OWASP compliance, authentication/authorization, data protection, injection attacks
- **Code Quality**: Maintainability, readability, complexity, duplication, naming conventions, design patterns
- **Best Practices**: Framework conventions, ecosystem standards, idioms, community patterns, linting compliance
- **Performance**: Bottlenecks, inefficient algorithms, resource usage, scalability issues, caching opportunities

**AI Roles:**

🔴 **Codex (Technical Quality)**:
- Code structure and organization
- Design patterns and anti-patterns
- Technical debt identification
- Implementation quality

🟡 **Gemini (Ecosystem Best Practices)**:
- Framework/language conventions
- Community standards
- Third-party library usage
- Ecosystem integration

🔵 **Claude (Security & Integration)**:
- Security vulnerabilities
- Authentication/authorization
- Data validation and sanitization
- Cross-cutting concerns

**Validation Gate**: Debate must complete with outputs from all 3 providers.

---

### 🛡️ STEP 3: Quality Scoring (BLOCKING)

**You MUST calculate scores across 4 dimensions:**

After debate completion, analyze the debate outputs and score each dimension:

#### Dimension 1: Code Quality (25%)
- **Excellent (23-25)**: Clean, maintainable, well-structured, follows best practices
- **Good (18-22)**: Generally good quality with minor improvements needed
- **Fair (13-17)**: Moderate issues, refactoring recommended
- **Poor (0-12)**: Significant quality problems, major refactoring required

**Scoring Criteria:**
- Readability and clarity: 7 points
- Design patterns and structure: 7 points
- Complexity management: 6 points
- Maintainability: 5 points

#### Dimension 2: Security (35%)
- **Excellent (32-35)**: No vulnerabilities, security best practices followed
- **Good (25-31)**: Minor security improvements recommended
- **Fair (18-24)**: Moderate security concerns requiring attention
- **Poor (0-17)**: Critical security vulnerabilities present

**Scoring Criteria:**
- Input validation and sanitization: 10 points
- Authentication and authorization: 10 points
- Data protection and encryption: 8 points
- OWASP top 10 compliance: 7 points

#### Dimension 3: Best Practices (20%)
- **Excellent (18-20)**: Exemplary adherence to ecosystem standards
- **Good (14-17)**: Follows most conventions with minor deviations
- **Fair (10-13)**: Some standards violations, improvements needed
- **Poor (0-9)**: Significant deviations from best practices

**Scoring Criteria:**
- Framework conventions: 7 points
- Language idioms: 6 points
- Community standards: 4 points
- Documentation and comments: 3 points

#### Dimension 4: Completeness (20%)
- **Excellent (18-20)**: Fully implemented, well-tested, production-ready
- **Good (14-17)**: Minor gaps, mostly complete
- **Fair (10-13)**: Noticeable gaps, additional work needed
- **Poor (0-9)**: Significant missing functionality or tests

**Scoring Criteria:**
- Feature completeness: 7 points
- Error handling: 6 points
- Test coverage: 4 points
- Edge case handling: 3 points

**Total Score Calculation:**
```
Total = Code Quality + Security + Best Practices + Completeness
Pass Threshold = 75/100
```

**Validation Gate**: All 4 dimensions must be scored with justification.

---

### 🛡️ STEP 4: Issue Extraction (BLOCKING)

**You MUST extract and categorize issues from debate outputs:**

Parse debate outputs and extract concrete issues. Categorize by severity:

#### Critical (Security) - Immediate action required
- Security vulnerabilities (SQL injection, XSS, CSRF, etc.)
- Authentication/authorization bypasses
- Data exposure or leakage
- Cryptographic failures

**Template:**
```markdown
**[CRITICAL]** <Brief description>
- **Location**: <file:line>
- **Impact**: <What could go wrong>
- **Fix**: <Recommended solution>
- **AI Source**: <Codex/Gemini/Claude>
```

#### High (Code Quality) - Should be addressed soon
- Design pattern violations
- High complexity or coupling
- Significant technical debt
- Performance bottlenecks

**Template:**
```markdown
**[HIGH]** <Brief description>
- **Location**: <file:line>
- **Problem**: <What's wrong>
- **Recommendation**: <How to fix>
- **AI Source**: <Codex/Gemini/Claude>
```

#### Medium (Best Practices) - Address in next iteration
- Convention violations
- Suboptimal patterns
- Missing documentation
- Linting violations

**Template:**
```markdown
**[MEDIUM]** <Brief description>
- **Location**: <file:line>
- **Issue**: <What should be improved>
- **Suggestion**: <Recommended change>
- **AI Source**: <Codex/Gemini/Claude>
```

#### Low (Completeness) - Nice to have
- Missing edge cases
- Incomplete error messages
- Optional optimizations
- Code style inconsistencies

**Template:**
```markdown
**[LOW]** <Brief description>
- **Location**: <file:line>
- **Enhancement**: <What could be better>
- **AI Source**: <Codex/Gemini/Claude>
```

**Validation Gate**: Issues must be extracted and categorized by severity.

---

### 🛡️ STEP 5: Validation Report (BLOCKING)

**You MUST generate comprehensive validation report:**

Create a report at `~/.claude-octopus/validation/<timestamp>/VALIDATION_REPORT.md`:

```markdown
# Validation Report

**Target**: <what was validated>
**Timestamp**: <ISO 8601 timestamp>
**Trigger**: <Pre-commit/Pre-deployment/Security audit/General review>
**Priorities**: <User's selected priorities>

---

## Executive Summary

**Overall Score**: <X>/100 - <PASS/FAIL>

<If PASS>
✅ The code meets quality standards (≥75/100). Minor improvements recommended.
</If PASS>

<If FAIL>
❌ The code does not meet quality standards (<75/100). Significant improvements required before deployment.
</If FAIL>

**Critical Issues**: <count>
**High Priority Issues**: <count>
**Medium Priority Issues**: <count>
**Low Priority Issues**: <count>

---

## Dimension Scores

### 🏗️ Code Quality: <X>/25
<Justification based on debate outputs>

**Strengths**:
- <Positive finding 1>
- <Positive finding 2>

**Areas for Improvement**:
- <Issue 1>
- <Issue 2>

---

### 🔒 Security: <X>/35
<Justification based on debate outputs>

**Strengths**:
- <Positive finding 1>
- <Positive finding 2>

**Vulnerabilities**:
- <Vulnerability 1>
- <Vulnerability 2>

---

### ✨ Best Practices: <X>/20
<Justification based on debate outputs>

**Adherence**:
- <Convention followed 1>
- <Convention followed 2>

**Deviations**:
- <Deviation 1>
- <Deviation 2>

---

### ✅ Completeness: <X>/20
<Justification based on debate outputs>

**Complete**:
- <Complete aspect 1>
- <Complete aspect 2>

**Gaps**:
- <Gap 1>
- <Gap 2>

---

## AI Perspectives

### 🔴 Codex Analysis (Technical Quality)
<Summary of Codex findings from debate>

**Key Points**:
- <Point 1>
- <Point 2>
- <Point 3>

---

### 🟡 Gemini Analysis (Ecosystem Best Practices)
<Summary of Gemini findings from debate>

**Key Points**:
- <Point 1>
- <Point 2>
- <Point 3>

---

### 🔵 Claude Analysis (Security & Integration)
<Summary of Claude findings from debate>

**Key Points**:
- <Point 1>
- <Point 2>
- <Point 3>

---

## Identified Issues

<Include all extracted issues from Step 4, grouped by severity>

### Critical Issues (<count>)
<List of critical issues>

### High Priority Issues (<count>)
<List of high priority issues>

### Medium Priority Issues (<count>)
<List of medium priority issues>

### Low Priority Issues (<count>)
<List of low priority issues>

---

## Recommendations

### Immediate Actions (Required)
1. <Action for critical issue 1>
2. <Action for critical issue 2>

### Short-term Improvements (This Sprint)
1. <Action for high priority issue 1>
2. <Action for high priority issue 2>

### Long-term Enhancements (Next Quarter)
1. <Action for medium priority issue 1>
2. <Action for completeness gap 1>

---

## Next Steps

<If PASS>
1. ✅ Code is ready for deployment
2. Address medium/low priority issues in future iterations
3. Consider security hardening for production environment
</If PASS>

<If FAIL>
1. ❌ DO NOT deploy until critical/high issues are resolved
2. Fix critical security vulnerabilities immediately
3. Address high priority code quality issues
4. Re-run validation after fixes
</If FAIL>

---

**Report Generated**: <timestamp>
**Validation Tool**: Claude Octopus v7.24.0
```

**Also create**: `~/.claude-octopus/validation/<timestamp>/ISSUES.md` with just the issues list for easy reference.

**Validation Gate**: Both files must be created and user must be shown the summary.

---

## After Completion

**You MUST display to the user:**

```
🛡️ **VALIDATION COMPLETE**

Overall Score: <X>/100 - <PASS ✅ / FAIL ❌>

📊 Dimension Breakdown:
  🏗️  Code Quality:     <X>/25
  🔒 Security:         <X>/35
  ✨ Best Practices:   <X>/20
  ✅ Completeness:     <X>/20

🐛 Issues Found:
  🔴 Critical:  <count>
  🟡 High:      <count>
  🟠 Medium:    <count>
  🔵 Low:       <count>

📄 Full Report: ~/.claude-octopus/validation/<timestamp>/VALIDATION_REPORT.md
📋 Issues List: ~/.claude-octopus/validation/<timestamp>/ISSUES.md

<If PASS>
✅ Code meets quality standards. Ready for deployment.
</If PASS>

<If FAIL>
❌ Code does not meet quality standards. Address critical/high issues before deployment.
</If FAIL>
```

**Then offer next actions:**
```
What would you like to do next?
1. View full validation report
2. Export to PPTX/PDF (via /octo:docs)
3. Create GitHub issues for findings
4. Re-run validation after fixes
5. Continue with deployment
```

---

## Prohibited Actions

❌ **CANNOT SKIP** interactive questions (Step 1)
❌ **CANNOT SIMULATE** orchestrate.sh execution (Step 2)
❌ **CANNOT SKIP** quality scoring (Step 3)
❌ **CANNOT SKIP** issue extraction (Step 4)
❌ **CANNOT SKIP** report generation (Step 5)
❌ **CANNOT** mark as complete without validation gates passing
❌ **CANNOT** create temporary files in plugin directory (use ~/.claude-octopus/validation/)

---

## Integration with Other Workflows

### With /octo:extract
```bash
# Extract patterns from reference implementation
/octo:extract https://example.com

# Validate against extracted patterns
/octo:validate src/ --reference extraction-results/
```

### With /octo:develop
```bash
# Build feature
/octo:develop user authentication

# Validate before commit
/octo:validate src/auth/ --focus security
```

### With /octo:debate
```bash
# Use debate for architectural decisions
/octo:debate "Should we use JWT or sessions?"

# Validate chosen implementation
/octo:validate src/auth/ --focus best-practices
```

---

## Notes

- **Pass threshold**: 75/100 (configurable in future versions)
- **Debate rounds**: 1 round (fast validation, can increase for deeper analysis)
- **Report storage**: `~/.claude-octopus/validation/<timestamp>/`
- **Export options**: Use `/octo:docs` to export validation report to PPTX/PDF
- **Re-validation**: Run again after addressing issues to verify fixes
- **Cost awareness**: Uses all 3 AI providers (Codex, Gemini, Claude) - approximately $0.03-0.10 per validation

---

## Version History

- **v1.0.0** (2025-02-03): Initial release
  - 5-step validation workflow
  - 4-dimensional quality scoring
  - Multi-AI debate integration
  - Automated issue extraction
  - Comprehensive reporting
