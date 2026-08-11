#!/usr/bin/env bash
# SubagentStop Hook — Capture last_assistant_message into agent result files
# Bridges Claude Code's native SubagentStop event with Octopus result files.
# When a Claude subagent finishes, this hook extracts last_assistant_message
# and writes it to the result_file declared in the agent-teams instruction JSON.
#
# Hook event: SubagentStop
# Feature gate: SUPPORTS_HOOK_LAST_MESSAGE (Claude Code v2.1.47+)
# Returns: exit 0 (allow stop) — no JSON output needed

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


WORKSPACE_DIR="${OCTOPUS_WORKSPACE:-${HOME}/.claude-octopus}"
TEAMS_DIR="${WORKSPACE_DIR}/agent-teams"

# Guard: python3 required for JSON parsing
if ! command -v python3 &>/dev/null; then
    exit 0
fi

# Read hook input from stdin
if [ -t 0 ]; then exit 0; fi
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null || true)
else
    INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && exit 0

# Extract last_assistant_message and agent_id — bail if message empty
LAST_MSG=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('last_assistant_message', ''))" 2>/dev/null) || true
[[ -z "$LAST_MSG" ]] && exit 0

AGENT_ID=$(printf '%s' "$INPUT" | python3 -c "
import sys, json; print(json.load(sys.stdin).get('agent_id', ''))" 2>/dev/null) || true

# v8.40.0: Capture agent_type from hook event for cost attribution (CC v2.1.69+)
AGENT_TYPE=$(printf '%s' "$INPUT" | python3 -c "
import sys, json; print(json.load(sys.stdin).get('agent_type', ''))" 2>/dev/null) || true

# Find the matching instruction JSON to get result_file path.
# Match by: agent_id (if populated), else oldest unfinished instruction.
RESULT_FILE=""
if [[ -d "$TEAMS_DIR" ]]; then
    RESULT_FILE=$(_OCTOPUS_TEAMS_DIR="$TEAMS_DIR" _OCTOPUS_AGENT_ID="$AGENT_ID" python3 -c "
import json, glob, os, sys
teams = os.environ['_OCTOPUS_TEAMS_DIR']
agent_id = os.environ.get('_OCTOPUS_AGENT_ID', '')
best, best_time = None, None
for f in sorted(glob.glob(os.path.join(teams, '*.json'))):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    rf = d.get('result_file', '')
    if not rf:
        continue
    if agent_id and d.get('agent_id') == agent_id:
        print(rf); sys.exit(0)
    if not d.get('agent_id') and d.get('dispatch_method') in ('agent_teams', 'resume'):
        mtime = os.path.getmtime(f)
        if best_time is None or mtime < best_time:
            best, best_time = rf, mtime
if best:
    print(best)
" 2>/dev/null) || true
fi
[[ -z "$RESULT_FILE" ]] && exit 0

# Security: validate result_file resolves within WORKSPACE_DIR (prevent path traversal)
RESOLVED_RESULT=$(_OCTO_PATH="$RESULT_FILE" python3 -c 'import os; print(os.path.realpath(os.environ["_OCTO_PATH"]))' 2>/dev/null) || exit 0
RESOLVED_WORKSPACE=$(_OCTO_PATH="$WORKSPACE_DIR" python3 -c 'import os; print(os.path.realpath(os.environ["_OCTO_PATH"]))' 2>/dev/null) || exit 0
case "$RESOLVED_RESULT" in
    "$RESOLVED_WORKSPACE"/*) ;; # OK — within workspace
    *) exit 0 ;; # Path traversal attempt — bail silently
esac

# Dedup: if the result file already has substantive output beyond headers, skip
if [[ -f "$RESULT_FILE" ]]; then
    BODY_LINES=$(sed '1,/^$/d' "$RESULT_FILE" 2>/dev/null | grep -cv '^$' 2>/dev/null) || BODY_LINES=0
    [[ "$BODY_LINES" -gt 2 ]] && exit 0
fi

# Write the captured message into the result file
{
    echo "## Output"
    echo '```'
    printf '%s\n' "$LAST_MSG"
    echo '```'
    echo ""
    echo "## Status: SUCCESS"
    echo "## Capture: SubagentStop hook (last_assistant_message)"
    # v8.40.0: Include agent_type for per-agent cost attribution (CC v2.1.69+)
    if [[ -n "$AGENT_TYPE" ]]; then
        echo "## Agent-Type: $AGENT_TYPE"
    fi
} >> "$RESULT_FILE"

# Complete the matching task in place. This hook can fire more than once for a
# native teammate, so counters must be derived from the task ledger rather than
# incremented blindly.
PROGRESS_FILE="${WORKSPACE_DIR}/progress.json"
if [[ -f "$PROGRESS_FILE" ]] && command -v python3 &>/dev/null; then
    python3 - "$PROGRESS_FILE" "$RESULT_FILE" <<'PYEOF' 2>/dev/null || true
import datetime, json, os, sys
path, result_file = sys.argv[1:3]
lock_handle = open(path + '.lock', 'a+b')
if os.name == 'nt':
    import msvcrt
    lock_handle.seek(0, os.SEEK_END)
    if lock_handle.tell() == 0:
        lock_handle.write(b'0')
        lock_handle.flush()
    lock_handle.seek(0)
    msvcrt.locking(lock_handle.fileno(), msvcrt.LK_LOCK, 1)
else:
    import fcntl
    fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
try:
    with open(path) as f:
        d = json.load(f)
    now = datetime.datetime.now(datetime.timezone.utc)
    terminal = {'completed', 'ok', 'degraded', 'failed', 'timeout', 'skipped'}
    for agent in d.get('agents', []):
        if agent.get('output_file') != result_file:
            continue
        if agent.get('status') not in terminal:
            agent['status'] = 'completed'
            agent['updated_at'] = now.strftime('%Y-%m-%dT%H:%M:%SZ')
            started = agent.get('started_at', '')
            try:
                start = datetime.datetime.fromisoformat(started.replace('Z', '+00:00'))
                agent['elapsed_ms'] = max(0, int((now - start).total_seconds() * 1000))
            except (TypeError, ValueError):
                agent['elapsed_ms'] = agent.get('elapsed_ms', 0)
        break
    agents = d.get('agents', [])
    finished = [a for a in agents if a.get('status') in terminal]
    d['total_agents'] = max(d.get('total_agents', 0), len(agents))
    d['completed_agents'] = len(finished)
    d['successful_agents'] = sum(a.get('status') in {'completed', 'ok', 'degraded'} for a in agents)
    d['failed_agents'] = sum(a.get('status') == 'failed' for a in agents)
    d['timeout_agents'] = sum(a.get('status') == 'timeout' for a in agents)
    d['skipped_agents'] = sum(a.get('status') == 'skipped' for a in agents)
    d['total_time_ms'] = sum(a.get('elapsed_ms', 0) for a in finished)
    d['total_cost'] = sum(a.get('cost', 0) for a in finished)
    tmp = path + '.tmp.' + str(os.getpid())
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
    os.replace(tmp, path)
except Exception:
    pass
finally:
    if os.name == 'nt':
        lock_handle.seek(0)
        msvcrt.locking(lock_handle.fileno(), msvcrt.LK_UNLCK, 1)
    else:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
    lock_handle.close()
PYEOF
fi

# Back-fill agent_id into the instruction JSON for correlation/continuation
if [[ -n "$AGENT_ID" && -d "$TEAMS_DIR" ]]; then
    _OCTOPUS_TEAMS_DIR="$TEAMS_DIR" _OCTOPUS_AGENT_ID="$AGENT_ID" \
    _OCTOPUS_RESULT_FILE="$RESULT_FILE" python3 -c "
import json, glob, os
teams = os.environ['_OCTOPUS_TEAMS_DIR']
agent_id = os.environ['_OCTOPUS_AGENT_ID']
result_file = os.environ['_OCTOPUS_RESULT_FILE']
for f in sorted(glob.glob(os.path.join(teams, '*.json'))):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    if d.get('result_file') == result_file and not d.get('agent_id'):
        d['agent_id'] = agent_id
        tmp = f + '.tmp'
        with open(tmp, 'w') as fh:
            json.dump(d, fh, indent=2)
        os.replace(tmp, f)
        break
" 2>/dev/null || true
fi

exit 0
