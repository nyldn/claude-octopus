---
name: octopus-quick-review
description: Fast pre-commit code review using multi-AI consensus
trigger: |
  Use this skill when the user says "review this code", "check this PR",
  "quality check the implementation", "review my changes", or "what's wrong with this code".
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - output_artifact_exists
---

# Quick Review Skill

Lightweight wrapper that triggers Claude Octopus grasp → tangle workflow for fast, consensus-driven code review.

## When This Skill Activates

Auto-invokes when user says:
- "review this code"
- "check this PR"
- "quality check the implementation"
- "review my changes"
- "what's wrong with this code"

## What It Does

**Two-Phase Workflow:**

1. **Grasp** (Define): Multi-agent consensus on what needs review
   - All agents independently identify issues
   - Synthesize into consensus list of concerns
   - Prioritize by severity and impact

2. **Tangle** (Develop): Parallel implementation review
   - Each agent reviews specific aspects (security, performance, maintainability)
   - Quality gate ensures ≥75% agreement
   - Synthesized findings with actionable recommendations

## Usage

```markdown
User: "Review this authentication module for security issues"

Claude: *Activates octopus-quick-review skill*
        *Runs: ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh grasp "Review authentication module"*
        *Then: ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh tangle "Implement review findings"*
```

## Implementation

When this skill is invoked, Claude should:

1. **Detect intent**: User wants code review
2. **Invoke grasp**: Get multi-agent consensus on review scope
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh grasp "[user's review request]"
   ```
3. **Invoke tangle**: Parallel review with quality gates
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh tangle "[synthesized review scope]"
   ```
4. **Present findings**: Format results for user

## Output Format

```markdown
## Review Summary

**Consensus Issues** (from grasp phase):
1. Authentication bypass in login handler
2. Missing rate limiting
3. Weak password validation

**Detailed Analysis** (from tangle phase):

### Security (Agent: Codex)
- Critical: SQL injection risk in user input
- Medium: Session tokens not rotated

### Performance (Agent: Gemini)
- High: N+1 queries in user lookup
- Low: Inefficient password hashing

**Quality Gate**: PASSED (85% agreement)

**Recommendations**:
1. Implement parameterized queries
2. Add rate limiting middleware
3. Use bcrypt with cost factor 12
```

## Why Use This Instead of Full Embrace?

| Aspect | Quick Review | Full Embrace |
|--------|-------------|--------------|
| Speed | 2-5 min | 5-10 min |
| Phases | 2 (grasp, tangle) | 4 (probe, grasp, tangle, ink) |
| Best For | Code review, PR checks | New features, architecture |
| Depth | Focused consensus | Deep research + validation |

## Configuration

Respects all octopus configuration:
- `--autonomy`: Control quality gate behavior
- `--quality`: Set consensus threshold (default 75%)
- `--provider`: Force specific AI provider
- `--cost-first`: Optimize for speed/cost

## Example Scenarios

### Scenario 1: PR Review
```
User: "Review PR #123 for security issues"
→ Grasp: Identify all security concerns
→ Tangle: Detailed OWASP Top 10 analysis
→ Output: Prioritized security findings
```

### Scenario 2: Performance Check
```
User: "Why is my API so slow?"
→ Grasp: Consensus on performance bottlenecks
→ Tangle: Parallel analysis (DB, network, compute)
→ Output: Optimization recommendations
```

### Scenario 3: Quick Sanity Check
```
User: "Does this look okay?"
→ Grasp: Quick consensus (basic issues only)
→ Tangle: Fast pass with --cost-first
→ Output: Green light or red flags
```

## Related Skills

- **octopus-security** (squeeze workflow) - For adversarial security testing
- **octopus-research** (probe workflow) - For deep investigation
- **Full embrace** - For complete Double Diamond workflow

## Technical Notes

- Uses existing grasp/tangle commands from orchestrate.sh
- No new code required - pure workflow coordination
- Leverages quality gates for reliability
- Session recovery supported (can resume if interrupted)
