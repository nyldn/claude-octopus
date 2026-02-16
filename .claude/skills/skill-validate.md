---
name: skill-validate
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

## ⚠️ EXECUTION CONTRACT (MANDATORY - BLOCKING)

**PRECEDENCE: This contract overrides any conflicting instructions in later sections.**

When the user invokes `/octo:validate <target>`, you MUST follow these steps sequentially. Each step is BLOCKING - you CANNOT skip or simulate any step.

### STEP 1: Scope Analysis (BLOCKING)

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

### STEP 2: Multi-AI Debate (BLOCKING)

**You MUST display visual indicators:**

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Validation Workflow
🛡️ Target: <what's being validated>

Validation Layers:
🔴 Codex CLI - Technical quality analysis
🟡 Gemini CLI - Ecosystem best practices
🔵 Claude - Security and integration review
```

**You MUST use the Bash tool to check provider availability:**

```bash
command -v codex && echo "CODEX_AVAILABLE" || echo "CODEX_UNAVAILABLE"
command -v gemini && echo "GEMINI_AVAILABLE" || echo "GEMINI_UNAVAILABLE"
```

**You MUST use the Bash tool to execute orchestrate.sh with debate mode:**

```bash
cd "${CLAUDE_PLUGIN_ROOT}"
./scripts/orchestrate.sh debate \
  --topic "Validation of <target>" \
  --rounds 1 \
  --focus "<user's selected priorities>" \
  --context "<validation trigger>" \
  --mode validation
```

**Validation Gate**: Debate must complete with outputs from all available providers.

### STEP 3: Quality Scoring (BLOCKING)

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

### STEP 4: Issue Extraction (BLOCKING)

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

### STEP 5: Validation Report (BLOCKING)

**You MUST generate comprehensive validation report:**

Create report at `~/.claude-octopus/validation/<timestamp>/VALIDATION_REPORT.md` and `~/.claude-octopus/validation/<timestamp>/ISSUES.md`.

**You MUST display summary to user:**

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
```

Then offer next actions:
1. View full validation report
2. Export to PPTX/PDF (via /octo:docs)
3. Create GitHub issues for findings
4. Re-run validation after fixes
5. Continue with deployment

**Validation Gate**: Both files must be created and user must be shown the summary.

### FORBIDDEN ACTIONS

❌ You CANNOT skip interactive questions (STEP 1)
❌ You CANNOT simulate orchestrate.sh execution (STEP 2)
❌ You CANNOT skip quality scoring (STEP 3)
❌ You CANNOT skip issue extraction (STEP 4)
❌ You CANNOT skip report generation (STEP 5)
❌ You CANNOT mark as complete without validation gates passing
❌ You CANNOT create temporary files in plugin directory (use ~/.claude-octopus/validation/)
❌ You CANNOT use Task/Explore agents as substitute for orchestrate.sh
❌ Do not substitute analysis/summary for required command execution

### COMPLETION GATE

Task is incomplete until all contract checks pass and outputs are reported.
Before presenting results, verify every MUST item was completed. Report any missing items explicitly.

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

## AI Roles Reference

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

---

## Debate Focus by Priority

- **Security**: Vulnerabilities, OWASP compliance, authentication/authorization, data protection, injection attacks
- **Code Quality**: Maintainability, readability, complexity, duplication, naming conventions, design patterns
- **Best Practices**: Framework conventions, ecosystem standards, idioms, community patterns, linting compliance
- **Performance**: Bottlenecks, inefficient algorithms, resource usage, scalability issues, caching opportunities

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
