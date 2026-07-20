#!/bin/bash
# Claude Octopus Quality Gate Hook (v8.43.0)
# Validates tangle output before continuing workflow
# Returns JSON decision: {"decision": "continue|block", "reason": "..."}
# v8.43: Added reference integrity check for cross-file dependencies
set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT

QUALITY_GATE_RESULTS_DIR="${HOME}/.claude-octopus/results"
QUALITY_GATE_ACK_DIR="${QUALITY_GATE_RESULTS_DIR}/quality-gate-ack"
QUALITY_GATE_HOOK_INPUT=""
if [[ $# -eq 0 && ! -t 0 ]]; then
    QUALITY_GATE_HOOK_INPUT=$(cat 2>/dev/null || true)
fi

quality_gate_latest_report() {
    ls -t "${QUALITY_GATE_RESULTS_DIR}"/tangle-validation-*.md 2>/dev/null | head -1 || true
}

quality_gate_report_value() {
    local report="$1" label="$2"
    awk -v prefix="## ${label}: " '
        index($0, prefix) == 1 {
            sub(prefix, "")
            sub(/\r$/, "")
            print
            exit
        }
    ' "$report" 2>/dev/null || true
}

quality_gate_fingerprint() {
    cksum "$1" 2>/dev/null | awk '{print $1 ":" $2}'
}

quality_gate_current_session() {
    local session="${CLAUDE_SESSION_ID:-${OCTOPUS_SESSION_ID:-}}"
    if [[ -z "$session" && -n "$QUALITY_GATE_HOOK_INPUT" ]] && command -v jq >/dev/null 2>&1; then
        session=$(printf '%s' "$QUALITY_GATE_HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
    fi
    printf '%s\n' "$session"
}

quality_gate_context_matches() {
    local report="$1"
    local report_workspace report_session current_workspace current_session
    report_workspace=$(quality_gate_report_value "$report" "Workspace")
    report_session=$(quality_gate_report_value "$report" "Session")
    current_workspace=$(pwd -P)
    current_session=$(quality_gate_current_session)

    # Legacy unscoped reports are retained as evidence but cannot globally
    # intercept unrelated sessions or workspaces.
    [[ -n "$report_workspace" && -n "$report_session" ]] || return 1
    [[ "$report_session" != "unknown" && -n "$current_session" ]] || return 1
    [[ "$report_workspace" == "$current_workspace" ]] || return 1
    [[ "$report_session" == "$current_session" ]] || return 1
}

quality_gate_find_matching_report() {
    local candidate
    while IFS= read -r candidate; do
        [[ -f "$candidate" ]] || continue
        if quality_gate_context_matches "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(ls -t "${QUALITY_GATE_RESULTS_DIR}"/tangle-validation-*.md 2>/dev/null || true)
    return 1
}

quality_gate_ack_file() {
    local report="$1" gate_id
    gate_id=$(quality_gate_report_value "$report" "Gate ID")
    [[ "$gate_id" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    printf '%s/%s.ack\n' "$QUALITY_GATE_ACK_DIR" "$gate_id"
}

quality_gate_is_acknowledged() {
    local report="$1" ack_file fingerprint
    ack_file=$(quality_gate_ack_file "$report") || return 1
    [[ -f "$ack_file" ]] || return 1
    fingerprint=$(quality_gate_fingerprint "$report")
    [[ "$(<"$ack_file")" == "$fingerprint" ]]
}

quality_gate_acknowledge() {
    local report="${1:-}"
    [[ -n "$report" && "$report" != "latest" ]] || report=$(quality_gate_find_matching_report 2>/dev/null || true)
    [[ -f "$report" ]] || { echo "No active quality gate for this workspace/session." >&2; return 1; }

    local gate_id ack_file fingerprint
    gate_id=$(quality_gate_report_value "$report" "Gate ID")
    ack_file=$(quality_gate_ack_file "$report") || {
        echo "Cannot acknowledge an unscoped legacy validation report." >&2
        return 1
    }
    fingerprint=$(quality_gate_fingerprint "$report")
    mkdir -p "$QUALITY_GATE_ACK_DIR"
    printf '%s\n' "$fingerprint" > "$ack_file"
    echo "Acknowledged quality gate ${gate_id}: ${report}"
}

quality_gate_status() {
    local report="${1:-}"
    [[ -n "$report" && "$report" != "latest" ]] || report=$(quality_gate_find_matching_report 2>/dev/null || true)
    [[ -f "$report" ]] || { echo "No active quality gate for this workspace/session."; return 0; }
    local gate_id status state="pending"
    gate_id=$(quality_gate_report_value "$report" "Gate ID")
    status=$(grep -E '^#{2,3}[[:space:]]+(Quality Gate|Status):' "$report" 2>/dev/null | head -1 || true)
    quality_gate_is_acknowledged "$report" && state="acknowledged"
    echo "Gate: ${gate_id:-legacy}"
    echo "State: ${state}"
    echo "Status: ${status:-unknown}"
    echo "Report: ${report}"
}

case "${1:-}" in
    --ack|ack|acknowledge)
        shift
        quality_gate_acknowledge "${1:-latest}"
        exit $?
        ;;
    --status|status)
        shift
        quality_gate_status "${1:-latest}"
        exit $?
        ;;
esac

VALIDATION_FILE=$(quality_gate_find_matching_report 2>/dev/null || true)

if [[ -f "$VALIDATION_FILE" ]]; then
    # Check if quality gate passed. `|| true` — grep-no-match must not cascade
    # under `set -o pipefail` and trigger the silent-fail path (issue #313).
    STATUS=$(grep -E '^#{2,3}[[:space:]]+(Quality Gate|Status):' "$VALIDATION_FILE" 2>/dev/null | head -1 || true)

    if ! quality_gate_is_acknowledged "$VALIDATION_FILE" && echo "$STATUS" | grep -qi "failed"; then
        echo '{"decision": "block", "reason": "Quality gate validation failed. Review tangle output before proceeding."}'
        exit 0
    fi

    if ! quality_gate_is_acknowledged "$VALIDATION_FILE" && echo "$STATUS" | grep -qi "warning"; then
        echo '{"decision": "block", "reason": "Quality gate has warnings. Review tangle output before proceeding."}'
        exit 0
    fi
fi

# Reference integrity check: scan recently created/modified files for broken references.
# Only defined here — called below when VALIDATION_FILE exists (i.e. tangle was recently run).
# Catches: HTML linking missing JS/CSS, scripts sourcing missing files, configs referencing missing paths
check_reference_integrity() {
    # Scope-local: disable -u because bash 3.2 (macOS CI) aborts (exit 134)
    # on `local arr=()` + `${#arr[@]}` when the array stays empty. We re-enable
    # -u on exit. See issue #313 PR #314 CI failure trail.
    set +u
    trap 'set -u' RETURN
    local issues=()

    # Find files modified in the last 10 minutes (likely tangle output)
    local recent_files
    recent_files=$(find . -maxdepth 5 -type f \( -name "*.html" -o -name "*.htm" \) -mmin -10 2>/dev/null || true)

    for file in $recent_files; do
        local dir
        dir=$(dirname "$file")

        # Check <script src="..."> references (skip http/https/CDN URLs)
        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            if [[ ! -f "$dir/$ref" && ! -f "$ref" ]]; then
                issues+=("$file references missing script: $ref")
            fi
        done < <(grep -oE '<script[^>]+src=["'"'"'][^"'"'"']+' "$file" 2>/dev/null | sed 's/.*src=["'"'"']//' | grep -v '^https\?://' || true)

        # Check <link href="..."> stylesheet references (skip http/https/CDN URLs)
        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            if [[ ! -f "$dir/$ref" && ! -f "$ref" ]]; then
                issues+=("$file references missing stylesheet: $ref")
            fi
        done < <(grep -oE '<link[^>]+href=["'"'"'][^"'"'"']+' "$file" 2>/dev/null | sed 's/.*href=["'"'"']//' | grep -v '^https\?://' | grep -v '^#' || true)
    done

    # Check shell scripts sourcing missing files
    local recent_scripts
    recent_scripts=$(find . -maxdepth 5 -type f -name "*.sh" -mmin -10 2>/dev/null || true)

    for file in $recent_scripts; do
        local dir
        dir=$(dirname "$file")

        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            # Skip variable references and command substitutions
            [[ "$ref" == *'$'* ]] && continue
            if [[ ! -f "$dir/$ref" && ! -f "$ref" ]]; then
                issues+=("$file sources missing file: $ref")
            fi
        done < <(grep -oE '^\s*(\.|source)\s+["'"'"'"]?[^"'"'"'"[:space:]]+' "$file" 2>/dev/null | sed -E 's/^[[:space:]]*(\.| source)[[:space:]]*//' | sed 's/^["'"'"'"]//' || true)
    done

    # Check docker-compose referencing missing Dockerfiles/configs
    local recent_compose
    recent_compose=$(find . -maxdepth 3 -type f \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) -mmin -10 2>/dev/null || true)

    for file in $recent_compose; do
        local dir
        dir=$(dirname "$file")

        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            if [[ ! -f "$dir/$ref" && ! -f "$ref" ]]; then
                issues+=("$file references missing file: $ref")
            fi
        done < <(grep -oE '^\s*(dockerfile|env_file|config):\s*\S+' "$file" 2>/dev/null | sed -E 's/^[[:space:]]*(dockerfile|env_file|config):[[:space:]]*//' || true)
    done

    if [[ ${#issues[@]} -gt 0 ]]; then
        local msg="Reference integrity check failed: ${issues[0]}"
        if [[ ${#issues[@]} -gt 1 ]]; then
            msg="$msg (and $((${#issues[@]}-1)) more)"
        fi
        echo "{\"decision\": \"block\", \"reason\": \"$msg\"}"
        # Human-readable stderr for Claude Code v2.1.41+
        printf '\n⚠️  Broken references detected:\n' >&2
        for issue in "${issues[@]}"; do
            printf '  • %s\n' "$issue" >&2
        done
        printf 'Fix: create the missing files or inline the code.\n' >&2
        exit 0
    fi
}

# Only scan for broken references when a tangle run actually happened recently.
# Skipping when VALIDATION_FILE is absent avoids scanning the plugin source tree
# in CI (where all .sh files are "recently modified" by the checkout), which
# triggered Abort trap: 6 on bash 3.2 macOS. See issue #313.
[[ -f "$VALIDATION_FILE" ]] && check_reference_integrity

# No validation file or quality gate passed
: # pass-through — current hook schema treats silence as continue
exit 0
