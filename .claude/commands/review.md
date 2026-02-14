---
command: review
description: Expert code review with comprehensive quality assessment and security analysis
---

# Review - Code Quality Assessment

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:review <arguments>`):

### Step 1: Ask Clarifying Questions

**CRITICAL: Before starting the review, use the AskUserQuestion tool to gather context:**

Ask 3 clarifying questions to ensure focused review:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What's the primary goal of this review?",
      header: "Goal",
      multiSelect: false,
      options: [
        {label: "Pre-commit check", description: "Quick review before committing"},
        {label: "Security focus", description: "Deep security vulnerability analysis"},
        {label: "Performance optimization", description: "Identify bottlenecks and improvements"},
        {label: "Architecture assessment", description: "Design patterns and structure review"}
      ]
    },
    {
      question: "What are your priority concerns?",
      header: "Priority",
      multiSelect: true,
      options: [
        {label: "Security vulnerabilities", description: "OWASP, authentication, data protection"},
        {label: "Performance issues", description: "Speed, efficiency, scalability"},
        {label: "Code maintainability", description: "Readability, complexity, structure"},
        {label: "Test coverage", description: "Testing adequacy and quality"}
      ]
    },
    {
      question: "Who is the audience for this review?",
      header: "Audience",
      multiSelect: false,
      options: [
        {label: "Just me", description: "Personal learning and improvement"},
        {label: "Team review", description: "Preparing for team code review"},
        {label: "Production release", description: "Pre-deployment quality gate"},
        {label: "External audit", description: "Client or compliance review"}
      ]
    }
  ]
})
```

**After receiving answers, incorporate them into the review prompt.**

### Step 2: Display Banner

Output this text to the user before executing:

```text
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider code review
📝 Review: <brief description of what's being reviewed>

Providers:
🔴 Codex CLI - Code quality analysis
🟡 Gemini CLI - Alternative patterns and edge cases
🔵 Claude - Synthesis and recommendations
```

### Step 3: Execute orchestrate.sh (USE BASH TOOL NOW)

**CRITICAL: You MUST execute this bash command. Do NOT skip it.**

```bash
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.plugins["octo@ayoahha-plugins"][0].installPath' ~/.claude/plugins/installed_plugins.json)}"
OCTOPUS_AGENT_TEAMS=legacy "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" auto "review <user's code review request>"
```

**WAIT for completion. Do NOT proceed until it finishes.**

If it fails, show the error. Do NOT fall back to direct code review.

### Step 4: Read Results

```bash
RESULT_FILE=$(find ~/.claude-octopus/results -name "delivery-*.md" 2>/dev/null | sort -r | head -n1)
if [[ -z "$RESULT_FILE" ]]; then
  echo "ERROR: No result file found"
  ls -lt ~/.claude-octopus/results/ 2>/dev/null | head -5
else
  echo "OK: $RESULT_FILE"
  cat "$RESULT_FILE"
fi
```

### Step 5: Present Results

Read the result file content and present it to the user with this footer:

```text
---
Multi-AI Code Review powered by Claude Octopus
Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude
Full report: <path to result file>
```

## PROHIBITIONS

- Do NOT review code yourself without orchestrate.sh
- Do NOT use Skill tool or Task tool as substitute
- Do NOT use `Task(octo:personas:code-reviewer)` or any Task agent
- If orchestrate.sh fails, tell the user - do NOT work around it

## Quick Usage

Just use natural language:
```text
"Review my authentication code for security issues"
"Code review the API endpoints in src/api/"
"Review this PR for quality and performance"
```

## What Gets Reviewed

- Code quality and style
- Security vulnerabilities (OWASP Top 10)
- Performance issues and optimizations
- Architecture and design patterns
- Test coverage and quality
- Error handling and edge cases

## Natural Language Examples

```text
"Review the auth module for security vulnerabilities"
"Quick review of my changes before I commit"
"Comprehensive code review of the payment processing code"
```
