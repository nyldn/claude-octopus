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
CAPTURE_LOCK_TARGET=""
_octo_hook_exit() {
    local c=$?
    if [[ -n "$CAPTURE_LOCK_TARGET" ]] && declare -F _octo_event_unlock >/dev/null 2>&1; then
        _octo_event_unlock "$CAPTURE_LOCK_TARGET"
    fi
    if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi
    return 0
}
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

AGENT_ID=$(printf '%s' "$INPUT" | python3 -c "
import sys, json; print(json.load(sys.stdin).get('agent_id', ''))" 2>/dev/null) || true

# v8.40.0: Capture agent_type from hook event for cost attribution (CC v2.1.69+)
AGENT_TYPE=$(printf '%s' "$INPUT" | python3 -c "
import sys, json; print(json.load(sys.stdin).get('agent_type', ''))" 2>/dev/null) || true

# Find the matching instruction JSON to get result_file path.
# Match by: agent_id (if populated), else oldest unfinished instruction.
RESULT_FILE=""
CONTRACT_RUN_ID=""
CONTRACT_SEAT_ID=""
if [[ -d "$TEAMS_DIR" ]]; then
    HOOK_MATCH=$(_OCTOPUS_TEAMS_DIR="$TEAMS_DIR" _OCTOPUS_AGENT_ID="$AGENT_ID" python3 -c "
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
        print('{}\t{}\t{}'.format(rf, d.get('run_id', ''), d.get('seat_id', ''))); sys.exit(0)
    if not d.get('agent_id') and d.get('dispatch_method') in ('agent_teams', 'resume'):
        mtime = os.path.getmtime(f)
        if best_time is None or mtime < best_time:
            best, best_time = d, mtime
if best:
    print('{}\t{}\t{}'.format(best.get('result_file', ''), best.get('run_id', ''), best.get('seat_id', '')))
" 2>/dev/null) || true
    if [[ "$HOOK_MATCH" == *$'\t'* ]]; then
        RESULT_FILE="${HOOK_MATCH%%$'\t'*}"
        _hook_meta="${HOOK_MATCH#*$'\t'}"
        CONTRACT_RUN_ID="${_hook_meta%%$'\t'*}"
        CONTRACT_SEAT_ID="${_hook_meta#*$'\t'}"
    fi
fi
[[ -z "$RESULT_FILE" ]] && exit 0

# Security: validate result_file resolves within WORKSPACE_DIR (prevent path traversal)
RESOLVED_RESULT=$(_OCTO_PATH="$RESULT_FILE" python3 -c 'import os; print(os.path.realpath(os.environ["_OCTO_PATH"]))' 2>/dev/null) || exit 0
RESOLVED_WORKSPACE=$(_OCTO_PATH="$WORKSPACE_DIR" python3 -c 'import os; print(os.path.realpath(os.environ["_OCTO_PATH"]))' 2>/dev/null) || exit 0
case "$RESOLVED_RESULT" in
    "$RESOLVED_WORKSPACE"/*) ;; # OK — within workspace
    *) exit 0 ;; # Path traversal attempt — bail silently
esac

_octo_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F _octo_event_lock >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${_octo_hook_dir}/../scripts/lib/events.sh" 2>/dev/null || true
fi
CAPTURE_LOCK_TARGET="${RESOLVED_RESULT}.capture"
if ! _octo_event_lock "$CAPTURE_LOCK_TARGET"; then
    CAPTURE_LOCK_TARGET=""
    exit 0
fi

HOOK_CONTRACT_STATUS="completed"
if [[ -n "$CONTRACT_SEAT_ID" ]]; then
    # shellcheck source=/dev/null
    source "${_octo_hook_dir}/../scripts/lib/run-contract.sh" 2>/dev/null || true
    [[ -n "$CONTRACT_RUN_ID" ]] && export OCTOPUS_RUN_ID="$CONTRACT_RUN_ID"

    # Validate the provider-authored message itself. Result headers are wrapper
    # text and must not make an empty or placeholder response look usable.
    MESSAGE_CHECK="$(mktemp "${WORKSPACE_DIR}/.subagent-message.XXXXXX")" || MESSAGE_CHECK=""
    if [[ -n "$MESSAGE_CHECK" ]]; then
        printf '%s' "$LAST_MSG" > "$MESSAGE_CHECK"
    fi
    if [[ -z "$MESSAGE_CHECK" ]] || ! _octo_run_output_usable_file "$MESSAGE_CHECK"; then
        HOOK_CONTRACT_STATUS="failed"
    fi
fi

# Dedup the result body, but continue into progress reconciliation. A prior hook
# may have captured output while the progress lock was temporarily unavailable.
RESULT_ALREADY_CAPTURED=false
if [[ -f "$RESULT_FILE" ]]; then
    BODY_LINES=$(sed '1,/^$/d' "$RESULT_FILE" 2>/dev/null | grep -cv '^$' 2>/dev/null) || BODY_LINES=0
    [[ "$BODY_LINES" -gt 2 ]] && RESULT_ALREADY_CAPTURED=true
fi

# Write the captured message into the result file
if [[ "$RESULT_ALREADY_CAPTURED" != "true" && "$HOOK_CONTRACT_STATUS" == "completed" ]]; then
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
fi

if [[ -n "$CONTRACT_SEAT_ID" ]]; then
    latest_transition="$(run_contract_latest_transition "$CONTRACT_SEAT_ID" 2>/dev/null || true)"
    case "$latest_transition" in
        contributed|degraded|skipped|failed|timeout|cancelled) ;;
        *)
            if [[ "$HOOK_CONTRACT_STATUS" == "completed" ]]; then
                if ! octo_run_contract_finish_background "$CONTRACT_SEAT_ID" success "$RESULT_FILE" "" "" 0 "" "" "$MESSAGE_CHECK"; then
                    HOOK_CONTRACT_STATUS="failed"
                fi
            else
                octo_run_contract_finish_background "$CONTRACT_SEAT_ID" failed "$RESULT_FILE" "" \
                    "Native teammate returned unusable output" 1 "" >/dev/null 2>&1 || true
            fi
            ;;
    esac
    [[ -n "${MESSAGE_CHECK:-}" ]] && rm -f "$MESSAGE_CHECK"
fi

_octo_event_unlock "$CAPTURE_LOCK_TARGET"
CAPTURE_LOCK_TARGET=""

# Complete the matching task in place. This hook can fire more than once for a
# native teammate, so counters must be derived from the task ledger rather than
# incremented blindly.
PROGRESS_FILE="${WORKSPACE_DIR}/progress.json"
if [[ -f "$PROGRESS_FILE" ]] && command -v python3 &>/dev/null; then
    HOOK_LOG_FILE="/dev/null"
    if mkdir -p "${WORKSPACE_DIR}/logs" 2>/dev/null; then
        HOOK_LOG_FILE="${WORKSPACE_DIR}/logs/hook-errors.log"
    fi
    _OCTOPUS_HOOK_CONTRACT_STATUS="$HOOK_CONTRACT_STATUS" \
    python3 - "$PROGRESS_FILE" "$RESOLVED_RESULT" <<'PYEOF' 2>>"$HOOK_LOG_FILE" || true
import datetime, json, math, os, shutil, sys, time, uuid
path, result_file = sys.argv[1:3]
lock_dir = path + '.lock'

def positive_int_env(name, default):
    try:
        value = int(os.environ.get(name, str(default)))
        return value if value > 0 else default
    except (TypeError, ValueError):
        return default

wait_seconds = positive_int_env('OCTO_LOCK_WAIT_SECS', 5)
retry_ms = positive_int_env('OCTO_LOCK_RETRY_MILLIS', 100)
deadline = time.monotonic() + wait_seconds
lock_token = '{}-{}'.format(os.getpid(), uuid.uuid4().hex)
try:
    stale_age = max(1, int(os.environ.get('OCTO_LOCK_STALE_SECS', '30')))
except ValueError:
    stale_age = 30

def read_pid(directory):
    try:
        with open(os.path.join(directory, 'pid')) as f:
            return int(f.read().strip())
    except (OSError, TypeError, ValueError):
        return None

def pid_is_alive(owner):
    if owner is None:
        return False
    try:
        os.kill(owner, 0)
        return True
    except PermissionError:
        return True
    except ProcessLookupError:
        return False

def lock_age_seconds(directory):
    try:
        with open(os.path.join(directory, 'ts')) as f:
            timestamp = int(f.read().strip())
        return max(0, time.time() - timestamp)
    except (OSError, TypeError, ValueError):
        return None

def lock_is_stale(directory):
    owner = read_pid(directory)
    age = lock_age_seconds(directory)
    if owner is not None:
        if not pid_is_alive(owner):
            return True
        # A live PID normally proves ownership. Bound that trust so a PID
        # recycled after a crash cannot preserve an abandoned lock forever.
        return age is not None and age >= stale_age * 10
    return age is not None and age >= stale_age

def restore_live_lock(stale_dir):
    try:
        os.rename(stale_dir, lock_dir)
        return
    except OSError:
        # Never delete a lock after discovering that its owner is alive. The
        # identity token below prevents that owner from releasing a successor.
        return

def release_owned_lock():
    try:
        with open(os.path.join(lock_dir, 'token')) as f:
            current = f.read().strip()
        if current == lock_token:
            shutil.rmtree(lock_dir, ignore_errors=True)
    except OSError:
        pass

def safe_number(value, default=0):
    if isinstance(value, bool) or value is None:
        return default
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(number) or number < 0:
        return default
    return int(number) if number.is_integer() else number

acquired = False
try:
    while True:
        created = False
        try:
            os.mkdir(lock_dir)
            created = True
            with open(os.path.join(lock_dir, 'pid'), 'w') as f:
                f.write(str(os.getpid()))
            with open(os.path.join(lock_dir, 'ts'), 'w') as f:
                f.write(str(int(time.time())))
            with open(os.path.join(lock_dir, 'token'), 'w') as f:
                f.write(lock_token)
            acquired = True
            break
        except FileExistsError:
            if os.path.isdir(lock_dir) and lock_is_stale(lock_dir):
                stale_dir = lock_dir + '.stale.' + lock_token
                try:
                    os.rename(lock_dir, stale_dir)
                    if lock_is_stale(stale_dir):
                        shutil.rmtree(stale_dir, ignore_errors=True)
                    else:
                        restore_live_lock(stale_dir)
                    continue
                except OSError:
                    pass
            if time.monotonic() >= deadline:
                raise TimeoutError('timed out acquiring progress lock')
            time.sleep(retry_ms / 1000.0)
        except OSError:
            if created:
                shutil.rmtree(lock_dir, ignore_errors=True)
            raise

    with open(path) as f:
        d = json.load(f)
    now = datetime.datetime.now(datetime.timezone.utc)
    terminal = {'completed', 'ok', 'degraded', 'failed', 'timeout', 'skipped'}
    for agent in d.get('agents', []):
        stored = agent.get('output_file') or ''
        if stored and not os.path.isabs(stored):
            stored = os.path.join(os.path.dirname(path), stored)
        if not stored or os.path.realpath(stored) != result_file:
            continue
        if agent.get('status') not in terminal:
            agent['status'] = 'failed' if os.environ.get('_OCTOPUS_HOOK_CONTRACT_STATUS') == 'failed' else 'completed'
            agent['updated_at'] = now.strftime('%Y-%m-%dT%H:%M:%SZ')
            started = agent.get('started_at', '')
            try:
                start = datetime.datetime.fromisoformat(started.replace('Z', '+00:00'))
                agent['elapsed_ms'] = max(0, int((now - start).total_seconds() * 1000))
            except (TypeError, ValueError):
                agent['elapsed_ms'] = safe_number(agent.get('elapsed_ms'))
        break
    agents = d.get('agents', [])
    finished = [a for a in agents if a.get('status') in terminal]
    d['total_agents'] = max(int(safe_number(d.get('total_agents'))), len(agents))
    d['completed_agents'] = len(finished)
    d['successful_agents'] = sum(a.get('status') in {'completed', 'ok', 'degraded'} for a in agents)
    d['failed_agents'] = sum(a.get('status') == 'failed' for a in agents)
    d['timeout_agents'] = sum(a.get('status') == 'timeout' for a in agents)
    d['skipped_agents'] = sum(a.get('status') == 'skipped' for a in agents)
    d['total_time_ms'] = sum(safe_number(a.get('elapsed_ms')) for a in finished)
    d['total_cost'] = sum(safe_number(a.get('cost')) for a in finished)
    tmp = path + '.tmp.' + str(os.getpid())
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
    os.replace(tmp, path)
except Exception as exc:
    print('[hook:subagent-result-capture.sh] progress update failed: {}: {}'.format(
        type(exc).__name__, exc), file=sys.stderr)
finally:
    if acquired:
        release_owned_lock()
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
