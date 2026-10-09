#!/usr/bin/env bash
_provider_lockout_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_provider_lockout_agent_spec_ready=false
if source "${_provider_lockout_dir}/agent-spec.sh" 2>/dev/null \
    && declare -F octo_agent_spec_provider >/dev/null 2>&1 \
    && declare -F octo_agent_spec_slug >/dev/null 2>&1; then
    _provider_lockout_agent_spec_ready=true
fi
# ═══════════════════════════════════════════════════════════════════════════════
# lib/provider-lockout.sh — single owner of the provider lockout + history protocol
# ═══════════════════════════════════════════════════════════════════════════════
#
# These seven functions were previously defined TWICE, in lib/quality.sh and
# lib/provider-routing.sh, identical except for the fallback provider. Because
# orchestrate.sh sources quality.sh (:194) before provider-routing.sh (:205),
# the routing copy silently won and a locked codex fell back to `gemini` —
# whose free tier is sunset and returns IneligibleTierError, so the recovery
# path routed into a known-dead seat.
#
# Extracting to one file rather than deleting one copy keeps standalone
# consumers working: several tests source provider-routing.sh alone and call
# append_provider_history / read_provider_history / build_provider_context.
#
# Fallback policy: codex -> agy -> claude-sonnet. agy is the current Google
# seat; gemini is not a valid recovery target while its tier is sunset.
#
# Functions: lock_provider, is_provider_locked, get_alternate_provider,
#            reset_provider_lockouts, append_provider_history,
#            read_provider_history, build_provider_context

lock_provider() {
    local provider="$1"
    # v9.5: bash builtin word check (zero subshells)
    if [[ " $LOCKED_PROVIDERS " != *" $provider "* ]]; then
        LOCKED_PROVIDERS="${LOCKED_PROVIDERS:+$LOCKED_PROVIDERS }$provider"
        log WARN "Provider locked out: $provider (will not self-revise)"
    fi
}

is_provider_locked() {
    local provider="$1"
    [[ " $LOCKED_PROVIDERS " == *" $provider "* ]]
}

get_alternate_provider() {
    local locked_provider="$1"
    case "$locked_provider" in
        codex|codex-fast|codex-mini)
            if ! is_provider_locked "agy"; then
                echo "agy"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            else
                echo "$locked_provider"  # All locked, use original
            fi
            ;;
        gemini|gemini-fast)
            # Present in the provider-routing.sh copy but not the quality.sh one.
            # Neither file had complete coverage: without this arm a locked
            # gemini falls through to *) and is offered itself as its own
            # alternate, so the lockout never routes anywhere.
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            else
                echo "$locked_provider"
            fi
            ;;
        agy|agy-research|antigravity)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            else
                echo "$locked_provider"
            fi
            ;;
        claude-sonnet|claude*)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "agy"; then
                echo "agy"
            else
                echo "$locked_provider"
            fi
            ;;
        *)
            echo "$locked_provider"
            ;;
    esac
}

reset_provider_lockouts() {
    if [[ -n "$LOCKED_PROVIDERS" ]]; then
        log INFO "Resetting provider lockouts (were: $LOCKED_PROVIDERS)"
    fi
    LOCKED_PROVIDERS=""
}

provider_history_file_key() {
    local provider key
    [[ "${_provider_lockout_agent_spec_ready:-false}" == true ]] || return 127
    provider="$(octo_agent_spec_provider "${1:-unknown}")" || return $?
    key="$(octo_agent_spec_slug "$provider")" || return $?
    case "$key" in
        ""|.|..) key="unknown" ;;
    esac
    printf '%s\n' "$key"
}

provider_history_lock() {
    # Match event/lifecycle admission: utility mkdir statuses can race. Keep
    # the bounded retry beside the kernel call and fail closed without Python.
    command -v python3 >/dev/null 2>&1 || return 1
    python3 - "${1}.lock" <<'PY'
import os
import sys
import time

for attempt in range(50):
    try:
        os.mkdir(sys.argv[1])
    except FileExistsError:
        if attempt < 49:
            time.sleep(0.02)
    except OSError:
        sys.exit(1)
    else:
        sys.exit(0)
sys.exit(1)
PY
}

provider_history_unlock() {
    rmdir "${1}.lock" 2>/dev/null || true
}

# v8.18.0 Feature: Per-Provider History Files
# Each provider accumulates project-specific knowledge in .octo/providers/{name}-history.md

append_provider_history() {
    case "${OCTOPUS_PROVIDER_HISTORY:-on}" in
        off|false|0|no) return 0 ;;
    esac

    local provider history_key
    [[ "${_provider_lockout_agent_spec_ready:-false}" == true ]] || return 127
    provider="$(octo_agent_spec_provider "$1")" || return $?
    history_key="$(provider_history_file_key "$provider")" || return $?
    local phase="$2"
    local task_brief="$3"
    local learned="$4"

    local history_dir="${WORKSPACE_DIR}/.octo/providers"
    local history_file="$history_dir/${history_key}-history.md"
    mkdir -p "$history_dir"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Model-qualified seats for one provider share this file. Serialize the full
    # append+trim transaction so one seat's trim cannot clobber another's append.
    # History is best-effort: if the lock cannot be acquired promptly, skip the
    # diagnostic write rather than falling back to an unsafe concurrent update.
    if ! provider_history_lock "$history_file"; then
        log WARN "Could not acquire provider history lock for $provider; skipping history append"
        return 0
    fi

    local history_rc=0 tmp_file=""
    if cat >> "$history_file" << HISTEOF
### ${phase} | ${timestamp}
**Task:** ${task_brief:0:100}
**Learned:** ${learned:0:200}
---
HISTEOF
    then
        :
    else
        history_rc=$?
    fi

    if [[ "$history_rc" -eq 0 ]]; then
        # Cap at 50 entries: count entries and trim oldest if exceeded.
        local entry_count
        entry_count=$(grep -c "^### " "$history_file" 2>/dev/null) || entry_count=0
        if [[ "$entry_count" -gt 50 ]]; then
            local excess=$((entry_count - 50)) trim_line
            trim_line=$(grep -n "^### " "$history_file" | sed -n "$((excess + 1))p" | cut -d: -f1)
            if [[ -n "$trim_line" && "$trim_line" -gt 1 ]]; then
                tmp_file=$(mktemp "${history_file}.tmp.XXXXXX") || history_rc=1
                if [[ "$history_rc" -eq 0 ]]; then
                    tail -n "+$trim_line" "$history_file" > "$tmp_file" && mv "$tmp_file" "$history_file" || history_rc=1
                fi
            fi
        fi
    fi

    [[ -z "$tmp_file" || ! -e "$tmp_file" ]] || rm -f "$tmp_file" 2>/dev/null || true
    provider_history_unlock "$history_file"

    if [[ "$history_rc" -ne 0 ]]; then
        log WARN "Provider history update failed for $provider"
        return "$history_rc"
    fi

    log DEBUG "Appended provider history for $provider (phase: $phase)"
}

read_provider_history() {
    case "${OCTOPUS_PROVIDER_HISTORY:-on}" in
        off|false|0|no) return 0 ;;
    esac

    local provider history_key
    [[ "${_provider_lockout_agent_spec_ready:-false}" == true ]] || return 127
    provider="$(octo_agent_spec_provider "$1")" || return $?
    history_key="$(provider_history_file_key "$provider")" || return $?
    local history_file="${WORKSPACE_DIR}/.octo/providers/${history_key}-history.md"

    if [[ -f "$history_file" ]]; then
        cat "$history_file"
    fi
}

build_provider_context() {
    local agent_type="$1"
    local base_provider
    [[ "${_provider_lockout_agent_spec_ready:-false}" == true ]] || return 127
    base_provider="$(octo_agent_spec_provider "$agent_type")" || return $?  # codex-fast -> codex; provider:model -> provider
    local history
    history=$(read_provider_history "$base_provider")

    if [[ -z "$history" ]]; then
        return
    fi

    # Truncate to max 2000 chars for prompt injection
    if [[ ${#history} -gt 2000 ]]; then
        history="${history:0:2000}..."
    fi

    echo "## Provider History (${base_provider})
Recent learnings from this project:
${history}"
}
