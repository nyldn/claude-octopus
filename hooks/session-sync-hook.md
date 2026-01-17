---
event: PreToolUse
tools: ["Bash"]
description: Syncs Claude session context before orchestrate.sh execution
---

# Session Sync PreToolUse Hook

This hook ensures Claude Code's session ID propagates to orchestrate.sh invocations for cross-session tracking.

## Purpose

When Claude Code invokes orchestrate.sh via the Bash tool, this hook:

1. Detects orchestrate.sh invocations
2. Ensures `CLAUDE_SESSION_ID` is exported to the environment
3. Adds session tracking context for debugging

## Trigger Conditions

- Tool is Bash
- Command contains `orchestrate.sh`

## Session ID Propagation (Claude Code v2.1.10)

The `${CLAUDE_SESSION_ID}` environment variable is available in Claude Code. This hook ensures it's properly passed through to orchestrate.sh:

```bash
# orchestrate.sh will detect this and use it for session tracking
export CLAUDE_SESSION_ID="${CLAUDE_SESSION_ID}"

# Session files will be named with the Claude session ID
# e.g., workflow-claude-abc123 instead of workflow-20260115-143022
```

## Benefits

1. **Cross-Session Correlation**: Track multiple orchestrate.sh runs within the same Claude Code session
2. **Debugging**: Easily find related log files and results
3. **Resume Support**: Better session resume when using the same Claude Code session

## Integration

The session ID is used in:
- `init_usage_tracking()` - Usage tracking file naming
- `init_session()` - Workflow session file naming
- `get_linked_sessions()` - Find all sessions from the same Claude Code session

## Example

When invoked from Claude Code session `abc123`:
- Usage file: `~/.claude-octopus/usage-session.json` with `session_id: "claude-abc123"`
- Session file: `~/.claude-octopus/session.json` with `session_id: "embrace-claude-abc123"`
- Results: All tagged with the Claude session for easy correlation
