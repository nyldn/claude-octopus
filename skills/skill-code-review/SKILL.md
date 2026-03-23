---
name: skill-code-review
version: 1.0.0
description: "Multi-AI code review combining Codex, Gemini, and Claude for quality, security, and architecture analysis. Use when: user says 'review this PR', 'check my code', 'security review', 'code review', or 'sanity check my changes'. Also activates for pre-merge validation and OWASP compliance checks."
---

# Code Review Skill

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-LLM Code Review`

Invokes the code-reviewer persona for thorough code analysis during the `ink` (deliver) phase.

## Quick Mode

For fast sanity checks (staged changes, small PRs), run just two phases:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh grasp "[review request]"
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh tangle "[synthesized scope]"
```

Use quick mode for "check this PR", "quick review", "sanity check my changes", or pre-commit checks. Use full review for PRs with security/architecture impact.

## Usage

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh spawn code-reviewer "Review this pull request for security issues"
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh auto "review the authentication implementation"
```

## Capabilities

- Security vulnerability detection (OWASP Top 10)
- Code quality and performance analysis
- Architecture and design pattern review
- TDD compliance and test-first evidence review
- Autonomous code generation risk detection

## Persona Reference

- Persona: `agents/personas/code-reviewer.md`
- CLI: `codex-review` | Model: `gpt-5.2-codex` | Phases: `ink`

## Example Prompts

```
"Review this PR for OWASP Top 10 vulnerabilities"
"Analyze the error handling in src/api/"
"Check for memory leaks in the connection pool"
"Review the test coverage for the auth module"
```

---

## Autonomous Implementation Review

When review context indicates `AI-assisted`, `Autonomous / Dark Factory`, or unclear provenance, raise the rigor bar.

### TDD Evidence

Check for red-green-refactor signs:
- Were tests added before or alongside production changes?
- Are tests behavior-defining (not just snapshot/mock-heavy)?
- Is production code the minimum needed to satisfy tests?
- If evidence is missing, mark TDD compliance as unknown.

### Autonomous Codegen Risk Patterns

Elevate findings for these high-autonomy patterns:
- Option-heavy APIs not justified by tests or requirements
- TODO/FIXME-driven control flow or dead "future ready" branches
- Mock/fake/dummy behavior leaking into production paths
- Unwired components or code without an execution path
- Broad catch blocks, missing logs, or weak operational visibility
- Missing rollback notes or migration guards

### Review Output Addendum

```markdown
## TDD / Autonomy Assessment

- Provenance: Human-authored | AI-assisted | Autonomous / Dark Factory | Unknown
- TDD evidence: Confirmed | Partial | Unknown
- Autonomous risk signals: None | Minor | Significant
- Recommendation: Ship | Fix before merge | Re-run with /octo:tdd or tighter supervision
```

---

## Implementation Completeness Verification

After review, run stub detection on changed files to verify completeness.

### Stub Detection

```bash
# Get changed source files
changed_files=$(git diff --name-only ${COMMIT_RANGE:-HEAD~1..HEAD} | grep -E "\.(ts|tsx|js|jsx|py|go)$")
```

For each file, check for:
1. **TODO/FIXME/PLACEHOLDER** comments
2. **Empty function bodies** (`function(){}`-style)
3. **Suspicious null/undefined returns**
4. **Low substantive line count** in components (<10 lines)
5. **Mock/test/dummy data** in production paths

### When to Block Merge

**BLOCKING:** Empty function bodies, mock data in production paths, unwired components, API endpoints returning empty objects.

**NON-BLOCKING:** TODO/FIXME comments, intentional null returns, low line count if appropriate.

Reference: `.claude/references/stub-detection.md`

---

## Post Review to PR

After generating the review synthesis, detect open PRs on the current branch via `gh pr list` and offer to post findings as a PR comment.

**Auto-post** when invoked as part of `/octo:deliver`, `/octo:factory`, or `/octo:embrace`.
**Ask first** when invoked standalone via `/octo:review`.

```bash
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
PR_NUM=$(gh pr list --head "$CURRENT_BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
[[ -n "$PR_NUM" ]] && gh pr comment "$PR_NUM" --body "$REVIEW_BODY"
```
