# Workflow Skills: Quick Access to Octopus Patterns

Claude Octopus includes **workflow skills** - lightweight wrappers that auto-invoke common multi-AI workflows. These activate automatically when you use certain phrases.

## 🔍 Quick Code Review (`/co:review`)

**Auto-activates when you say:**
- "review this code"
- "check this PR"
- "quality check"
- "what's wrong with this code"

**What it does:** Runs define (consensus) → develop (parallel review) workflow
- Faster than full embrace (2-5 min vs 5-10 min)
- Multi-agent consensus on issues
- Quality gates ensure ≥75% agreement
- Actionable recommendations

**Example:**
```
User: "Review my authentication module for security issues"
→ Define: Multi-agent consensus on security concerns
→ Develop: Parallel review (OWASP, performance, maintainability)
→ Output: Prioritized findings with fixes
```

## 🔬 Deep Research (`/co:research`)

**Auto-activates when you say:**
- "research this topic"
- "investigate how X works"
- "explore different approaches"
- "what are the options for Y"

**What it does:** Runs discover (probe) workflow with 4 parallel perspectives
- Researcher: Technical analysis and documentation
- Designer: UX patterns and user impact
- Implementer: Code examples and implementation
- Reviewer: Best practices and gotchas

**Example:**
```
User: "Research state management options for React"
→ Discover: 4 agents research from different angles
→ Synthesis: AI-powered comparison and recommendation
→ Output: Decision matrix with pros/cons
```

## 🛡️ Adversarial Security (`/co:security`)

**Auto-activates when you say:**
- "security audit"
- "find vulnerabilities"
- "red team review"
- "pentest this code"

**What it does:** Runs squeeze (red team) workflow
- Blue Team: Reviews defenses
- Red Team: Finds vulnerabilities with exploit PoCs
- Remediation: Fixes all issues
- Validation: Confirms security clearance

**Example:**
```
User: "Security audit the authentication module"
→ Blue Team: Identify attack surface
→ Red Team: Generate 6 exploit proofs of concept
→ Remediation: Patch all vulnerabilities
→ Validation: Re-test and confirm fixes
```

## 📊 When to Use Which Workflow

| Use Case | Workflow Skill | Time | Agents | Best For |
|----------|---------------|------|--------|----------|
| Code review | `/co:review` | 2-5 min | 2-3 | PR checks, quality gates |
| Research | `/co:research` | 2-3 min | 4 | Architecture decisions |
| Security testing | `/co:security` | 5-10 min | 2 (adversarial) | Finding vulnerabilities |
| Full workflow | `/co:embrace` | 5-10 min | 4-8 | New features, complete cycle |

## Architecture: Skills vs Orchestrator

Understanding the distinction:

**Claude Octopus = Orchestrator (Complex Workflows)**
- Multi-agent coordination
- Quality gates and validation
- Session recovery
- Structured workflows (Double Diamond)
- Best for: Architecture, features, comprehensive analysis

**Workflow Skills = Entry Points (Convenience)**
- Auto-invoked shortcuts
- Trigger specific orchestrator workflows
- Single-purpose and focused
- Best for: Common patterns, quick access

**Companion Skills = Domain Tools (Specialized)**
- Testing, design, deployment
- Work alongside orchestrator
- Routine, repetitive tasks
- Best for: Specific domains (UI, testing, docs)

**Example of all three working together:**
```
1. User: "octo research authentication patterns"
   → /co:research skill activates (entry point)
   → Triggers discover workflow (orchestrator)

2. User: "octo build authentication module"
   → Claude Octopus orchestrates embrace workflow
   → Agents generate implementation

3. User: "Test the authentication"
   → webapp-testing skill validates (domain tool)
   → Results feed back to Claude for review
```

---

## 🤖 Deep Autonomy Mode (Background Work)

**Auto-activates when you say:**
- "work on this in the background"
- "take the wheel"
- "autonomous mode"
- "finish this for me"

**What it does:** Enters a high-reliability, self-correcting mode for long-running tasks.
- **Reliability First**: Uses atomic file operations (`WriteFile`) instead of shell editing.
- **Self-Correcting**: Automatically loops (`/octo:loop`) and retries on failure without asking.
- **Quiet Mode**: Suppresses chatter, reporting only status via JSON or milestones.
- **Timeout Handling**: Uses extended timeouts for long builds/tests.

**Example:**
```
User: "Take the wheel and fix all linting errors in the background"
→ Activates Deep Autonomy Mode
→ Loops: Lint -> Parse -> Fix -> Verify
→ Retries if fix fails
→ Reports only when ALL errors are fixed or blocked
```

---

[← Back to README](../README.md)
