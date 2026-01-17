---
event: PreToolUse
tools: ["Bash", "Write", "Edit"]
description: Validates quality gates before file modifications during tangle/ink phases
---

# Quality Gate PreToolUse Hook

This hook enforces quality gates before allowing file modifications in Claude Octopus workflows.

## Purpose

When Claude Code executes tools that modify files (Bash, Write, Edit) during an active claude-octopus workflow, this hook:

1. Checks for active tangle/ink phase execution
2. Reads the quality gate status from validation reports
3. Returns additional context to inform Claude's decisions

## Trigger Conditions

- Tool is Bash, Write, or Edit
- Active claude-octopus workflow detected (session file exists)
- Current phase is `tangle` or `ink`

## Validation Logic

```bash
# Check for quality gate file
VALIDATION_FILE=$(ls -t ~/.claude-octopus/results/tangle-validation-*.md 2>/dev/null | head -1)

if [[ -f "$VALIDATION_FILE" ]]; then
    # Parse quality gate status
    STATUS=$(grep -E "^## (Quality Gate|Status):" "$VALIDATION_FILE" | head -1)

    if echo "$STATUS" | grep -q "FAILED"; then
        echo "Quality gate FAILED - review required before proceeding"
    fi
fi
```

## additionalContext Return (Claude Code v2.1.10)

This hook leverages the `additionalContext` feature (v2.1.9+) to inject workflow state into Claude's context before tool execution:

```json
{
  "octopus_workflow": {
    "phase": "tangle|ink",
    "quality_score": 85,
    "quality_status": "WARNING",
    "threshold": 75,
    "pending_reviews": 2
  },
  "session": {
    "id": "claude-abc123",
    "results_dir": "~/.claude-octopus/results/claude-abc123/",
    "plans_dir": "~/.claude-octopus/plans/claude-abc123/"
  },
  "providers": {
    "codex": "available",
    "gemini": "available"
  }
}
```

This additional context helps Claude make informed decisions during multi-agent orchestration.

## Response Behavior

| Quality Status | Hook Response |
|----------------|---------------|
| PASSED (>=90%) | `continue` - Allow tool execution |
| WARNING (75-89%) | `continue` with context warning |
| FAILED (<75%) | Provide context, request human review |

## Integration with CI Mode

When `CI_MODE=true` (detected via `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` or `CI` env vars):
- FAILED status automatically blocks tool execution
- No interactive prompts are shown
- GitHub Actions annotations are emitted

## Related Files

- `~/.claude-octopus/results/tangle-validation-*.md` - Quality gate reports
- `~/.claude-octopus/session.json` - Current session state
- `scripts/orchestrate.sh` - Main orchestration script
