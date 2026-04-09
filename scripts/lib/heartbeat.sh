#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# lib/heartbeat.sh — Heartbeat monitoring, dynamic timeouts, portable timeout
# Extracted from orchestrate.sh (v8.19.0 heartbeat + v7.16.0 timeout)
# ═══════════════════════════════════════════════════════════════════════════════

start_heartbeat_monitor() {
    local pid="$1"
    local task_id="$2"

    local heartbeat_dir="${WORKSPACE_DIR}/.octo/agents"
    mkdir -p "$heartbeat_dir"
    local heartbeat_file="$heartbeat_dir/${pid}.heartbeat"

    # Background process: touch heartbeat every 30s, self-terminate when PID dies
    (
        while kill -0 "$pid" 2>/dev/null; do
            touch "$heartbeat_file"
            sleep 30
        done
        rm -f "$heartbeat_file"
    ) &
    disown

    log DEBUG "Heartbeat monitor started for PID $pid (task: $task_id)"
}

check_agent_heartbeat() {
    local pid="$1"

    local heartbeat_file="${WORKSPACE_DIR}/.octo/agents/${pid}.heartbeat"

    if [[ ! -f "$heartbeat_file" ]]; then
        echo "missing"
        return
    fi

    # Get file modification time (macOS vs Linux compatible)
    local mod_time
    if stat -f %m "$heartbeat_file" &>/dev/null; then
        # macOS
        mod_time=$(stat -f %m "$heartbeat_file")
    else
        # Linux
        mod_time=$(stat -c %Y "$heartbeat_file")
    fi

    local now
    now=$(date +%s)
    local age=$((now - mod_time))

    if [[ $age -gt 90 ]]; then
        echo "stale"
    else
        echo "alive"
    fi
}

compute_dynamic_timeout() {
    local task_type="${1:-standard}"
    local prompt="${2:-}"
    local agent_type="${3:-}"  # v9.2.0: optional provider for per-provider caps

    # Env override takes precedence
    if [[ -n "${OCTOPUS_AGENT_TIMEOUT:-}" ]]; then
        echo "$OCTOPUS_AGENT_TIMEOUT"
        return
    fi

    # v9.2.0: Provider-specific timeout caps (OctoBench data)
    # Codex: consistently 120-183s, cap at 150s for probe tasks
    # Gemini: consistently 34-113s, cap at 90s for probe tasks
    # Claude-sonnet: consistently 35-46s, cap at 60s for probe tasks
    local provider_cap=""
    case "$agent_type" in
        codex*)     provider_cap=150 ;;
        gemini*)    provider_cap=90 ;;
        claude-sonnet*|sonnet*) provider_cap=60 ;;
        perplexity*) provider_cap=45 ;;
    esac

    # Response mode mapping
    local response_mode="${OCTOPUS_RESPONSE_MODE:-auto}"
    case "$response_mode" in
        direct|lightweight)
            echo "60"
            return
            ;;
    esac

    # v8.40.0: When CC has memory leak fixes (v2.1.63+), long sessions are stable —
    # allow longer timeouts for complex tasks since agent sessions won't degrade
    local leak_safe_boost=0
    if [[ "$SUPPORTS_MEMORY_LEAK_FIXES" == "true" ]]; then
        leak_safe_boost=60
    fi

    # Task type mapping
    case "$task_type" in
        direct|lightweight|trivial)
            echo "60"
            ;;
        full|premium|complex)
            echo "$((300 + leak_safe_boost))"
            ;;
        crossfire|debate)
            echo "$((180 + leak_safe_boost))"
            ;;
        security|audit)
            echo "$((240 + leak_safe_boost))"
            ;;
        *)
            local base_timeout=$((120 + leak_safe_boost))
            # Apply provider cap if set and lower than task-based timeout
            if [[ -n "$provider_cap" && "$provider_cap" -lt "$base_timeout" ]]; then
                echo "$provider_cap"
            else
                echo "$base_timeout"
            fi
            ;;
    esac
}

cleanup_heartbeat() {
    local pid="$1"
    rm -f "${WORKSPACE_DIR}/.octo/agents/${pid}.heartbeat"
}

# Portable timeout function (works on macOS and Linux)
# Prefers system timeout commands, falls back to manual implementation
run_with_timeout() {
    local timeout_secs="$1"
    shift

    local exit_code

    # v9.20.1: Detect if command is a shell function (e.g. perplexity_execute,
    # openrouter_execute). External timeout/gtimeout can only exec binaries —
    # shell functions require the in-process fallback path. (#255)
    local _cmd_is_function=false
    if [[ "$(type -t "$1" 2>/dev/null)" == "function" ]]; then
        _cmd_is_function=true
    fi

    # Use gtimeout (GNU) or timeout if available AND command is an external binary
    if [[ "$_cmd_is_function" == "false" ]] && command -v gtimeout &>/dev/null; then
        gtimeout "$timeout_secs" "$@"
        exit_code=$?
    elif [[ "$_cmd_is_function" == "false" ]] && command -v timeout &>/dev/null; then
        timeout "$timeout_secs" "$@"
        exit_code=$?
    else
        # Fallback with proper cleanup (also used for shell functions)
        local cmd_pid monitor_pid

        "$@" &
        cmd_pid=$!

        ( sleep "$timeout_secs" && kill -TERM "$cmd_pid" 2>/dev/null ) &
        monitor_pid=$!

        if wait "$cmd_pid" 2>/dev/null; then
            exit_code=0
        else
            exit_code=$?
        fi

        # Clean up monitor process
        kill "$monitor_pid" 2>/dev/null
        wait "$monitor_pid" 2>/dev/null
    fi

    # Enhanced timeout error messaging (v7.16.0 Feature 3)
    if [[ $exit_code -eq 124 ]] || [[ $exit_code -eq 143 ]]; then
        local timeout_mins=$((timeout_secs / 60))
        local recommended_timeout=$((timeout_secs * 2))
        local recommended_mins=$((recommended_timeout / 60))

        log ERROR "Operation timed out after ${timeout_secs}s (${timeout_mins}m)"
        echo "" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "⚠️  TIMEOUT EXCEEDED" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "" >&2
        echo "Operation exceeded the ${timeout_secs}s (${timeout_mins}m) timeout limit." >&2
        echo "" >&2
        echo "💡 Possible solutions:" >&2
        echo "   1. Increase timeout: --timeout ${recommended_timeout} (${recommended_mins}m)" >&2
        echo "   2. Simplify the prompt to reduce processing time" >&2
        echo "   3. Check provider API status for slowness" >&2
        echo "" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        return 124
    fi

    return $exit_code
}
