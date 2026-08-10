#!/bin/bash
# Claude Octopus Careful Mode Hook (v9.8.0)
# PreToolUse hook on Bash that warns before destructive command patterns.
# Activated by /octo:careful command (writes state file).
# Returns JSON decision: {"decision":"allow"} or {"permissionDecision":"ask","message":"..."}
#
# Kill switch: OCTO_CAREFUL_MODE=off — disables all destructive command checks
set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT

_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_HOOK_DIR/../scripts/lib/session-id.sh" 2>/dev/null || true

# Kill switch — respect user's choice to disable careful mode entirely
# (careful mode is opt-in via /octo:careful; OCTO_CAREFUL_MODE=off is the dedicated off-switch)
[[ "${OCTO_CAREFUL_MODE:-on}" == "off" ]] && exit 0

# Read tool input from stdin
if command -v timeout &>/dev/null; then
    INPUT=$(timeout 3 cat 2>/dev/null || true)
else
    INPUT=$(cat 2>/dev/null || true)
fi
[[ -z "$INPUT" ]] && INPUT='{}'

# Only gate Bash commands
TOOL_NAME=$(echo "$INPUT" | grep -o '"tool_name":"[^"]*"' 2>/dev/null | head -1 | cut -d'"' -f4 || true)
if [[ "$TOOL_NAME" != "Bash" ]]; then
    : # pass-through — current hook schema treats silence as continue
    exit 0
fi

# Check if careful mode is active
if declare -f octo_session_state_file >/dev/null 2>&1; then
    STATE_FILE=$(octo_session_state_file "careful" "txt" "$INPUT")
else
    STATE_FILE="/tmp/octopus-careful-${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-$$}}.txt"
fi
if [[ ! -f "$STATE_FILE" ]]; then
    : # pass-through — current hook schema treats silence as continue
    exit 0
fi

# Extract command from input — use jq if available, fall back to grep
# Note: grep-based extraction truncates at escaped quotes, so we also check raw INPUT
if command -v jq &>/dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || echo "")
else
    COMMAND=$(echo "$INPUT" | grep -o '"command":"[^"]*"' 2>/dev/null | head -1 | cut -d'"' -f4 || true)
fi
# Scan the extracted command when we have one. Only fall back to the raw
# payload when extraction produced nothing (grep-based extraction truncates at
# escaped quotes) — otherwise every unrelated field in the hook JSON, including
# cwd and transcript paths, becomes a match surface for the patterns below.
if [[ -n "$COMMAND" ]]; then
    CHECK_TEXT="$COMMAND"
else
    CHECK_TEXT="$INPUT"
fi
if [[ -z "$COMMAND" && -z "$INPUT" ]]; then
    : # pass-through — current hook schema treats silence as continue
    exit 0
fi

# ── Destructive pattern checks ────────────────────────────────────────

# 1. rm -rf — but allow safe exceptions (node_modules, dist, .next, __pycache__, build, coverage, .turbo)
if echo "$CHECK_TEXT" | grep -qE '(^|[^[:alnum:]_])rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-r\s+-f|-f\s+-r|--recursive\s+--force)'; then
    # Check if the target is a safe exception
    safe=false
    for safe_dir in node_modules dist .next __pycache__ build coverage .turbo; do
        if echo "$CHECK_TEXT" | grep -qE "rm\s+.*${safe_dir}(\s|$|/)"; then
            safe=true
            break
        fi
    done
    if [[ "$safe" == "false" ]]; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ Destructive command detected: rm -rf. This recursively force-deletes files. Confirm you want to proceed."}}'
        exit 0
    fi
fi

# 2. SQL destructive operations. A SQL-looking string alone is not execution: source
# searches and output commands routinely contain examples such as `DROP TABLE` and
# `TRUNCATE users`. Gate only when the statement is either a direct shell command or
# appears alongside a known SQL client. This keeps read-only grep/rg/printf commands
# quiet while retaining coverage for client flags, stdin pipes, and heredocs.
_octo_drop_pat='DROP\s+(TABLE|DATABASE)(\s+IF\s+EXISTS)?(\s+["'\''`]?[[:alnum:]_.$-]+["'\''`]?)?'
_octo_truncate_pat='TRUNCATE\s+["'\''`]?[[:alnum:]_.$-]+["'\''`]?(\s+["'\''`]?[[:alnum:]_.$-]+["'\''`]?)?'
_octo_sql_pat="${_octo_drop_pat}|${_octo_truncate_pat}"
_octo_sql_client_pat='(^|[;&|][[:space:]]*)((sudo|command|env)[[:space:]]+)?([[:alpha:]_][[:alnum:]_]*=[^[:space:]]+[[:space:]]+)*(psql|mysql|mariadb|sqlite3|sqlcmd|cockroach\s+sql)([[:space:]]|$)'
_octo_direct_sql_pat="^[[:space:]]*(${_octo_sql_pat})"

# ERE alternation alone cannot distinguish `TRUNCATE TABLE foo` from the
# incomplete `TRUNCATE TABLE`: the optional TABLE branch can backtrack and
# consume TABLE as the identifier. Inspect candidate tokens so TABLE requires a
# third token, while `TRUNCATE users` and quoted identifiers remain protected.
_octo_has_destructive_sql() {
    local drop_matches truncate_matches
    drop_matches=$(echo "$CHECK_TEXT" | grep -oiE "$_octo_drop_pat" || true)
    if [[ -n "$drop_matches" ]] && printf '%s\n' "$drop_matches" | awk '
        {
            if (NF < 3) next
            if (tolower($3) == "if") {
                if (NF < 5 || tolower($4) != "exists") next
                target = $5
            } else {
                target = $3
            }
            quote = substr(target, 1, 1)
            apostrophe = sprintf("%c", 39)
            if ((quote == "\"" || quote == "`" || quote == apostrophe) &&
                substr(target, length(target), 1) != quote) next
            found = 1
            exit
        }
        END { exit(found ? 0 : 1) }
    '; then
        return 0
    fi
    truncate_matches=$(echo "$CHECK_TEXT" | grep -oiE "$_octo_truncate_pat" || true)
    [[ -n "$truncate_matches" ]] || return 1
    printf '%s\n' "$truncate_matches" | awk '
        {
            raw = $2
            token = tolower(raw)
            gsub(/^["`]/, "", token)
            gsub(/["`;]$/, "", token)
            apostrophe = sprintf("%c", 39)
            first = substr(raw, 1, 1)
            quoted = (first == "\"" || first == "`" || first == apostrophe)
            if (token == "table" && !quoted && NF < 3) next
            target = (token == "table" && !quoted) ? $3 : $2
            quote = substr(target, 1, 1)
            if ((quote == "\"" || quote == "`" || quote == apostrophe) &&
                substr(target, length(target), 1) != quote) next
            found = 1
            exit
        }
        END { exit(found ? 0 : 1) }
    '
}

if _octo_has_destructive_sql \
    && { echo "$CHECK_TEXT" | grep -qiE "$_octo_sql_client_pat" \
        || echo "$CHECK_TEXT" | grep -qiE "$_octo_direct_sql_pat"; }; then
    matched=$(echo "$CHECK_TEXT" | grep -oiE "$_octo_sql_pat" | head -1)
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"⚠️ Destructive SQL detected: ${matched}. This permanently destroys data. Confirm you want to proceed.\"}}"
    exit 0
fi

# 3. git push --force / -f
# `-f` must be matched as a standalone flag token. The previous `.*-f` matched
# any branch name containing "-f" (e.g. `git push origin release-final`), so
# ordinary pushes were flagged as force pushes.
if echo "$CHECK_TEXT" | grep -qE 'git\s+push\s+([^|;&]*\s)?(-[a-zA-Z]*f|--force(-with-lease)?(=[^ ]*)?)(\s|$)'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ Destructive command detected: git push --force. This rewrites remote history and can cause data loss for collaborators. Confirm you want to proceed."}}'
    exit 0
fi

# 4. git reset --hard
if echo "$CHECK_TEXT" | grep -qE 'git\s+reset\s+--hard'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ Destructive command detected: git reset --hard. This discards all uncommitted changes. Confirm you want to proceed."}}'
    exit 0
fi

# 5. git checkout . / git restore . — only the WHOLE-TREE discard (`.` or bare `./`)
# should warn "discards all unstaged changes". Bare `\.` also matched a single dotfile
# (`git checkout .gitignore`), and `\.(/)` also matched a `./`-prefixed single path
# (`git checkout ./.gitignore`, `git restore ./.env`) — both discard one file, not all.
# Allow shell-equivalent quoting and `--`, but require the dot path to end at a
# shell boundary so dotfiles and `./subpaths` remain quiet.
if echo "$CHECK_TEXT" | grep -qE "git\\s+(checkout|restore)\\s+(--\\s+)?[\"']?\\.(/)?[\"']?([[:space:];|&]|$)"; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ Destructive command detected: git checkout/restore. This discards all unstaged changes. Confirm you want to proceed."}}'
    exit 0
fi

# 6. kubectl delete
if echo "$CHECK_TEXT" | grep -qE 'kubectl\s+delete'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"⚠️ Destructive command detected: kubectl delete. This removes Kubernetes resources. Confirm you want to proceed."}}'
    exit 0
fi

# 7. docker rm -f / docker system prune
if echo "$CHECK_TEXT" | grep -qE 'docker\s+rm\s+-f|docker\s+system\s+prune'; then
    matched=$(echo "$CHECK_TEXT" | grep -oE 'docker\s+(rm\s+-f|system\s+prune)' | head -1)
    echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"⚠️ Destructive command detected: ${matched}. This forcefully removes Docker resources. Confirm you want to proceed.\"}}"
    exit 0
fi

# All checks passed
: # pass-through — current hook schema treats silence as continue
exit 0
