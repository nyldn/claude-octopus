#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# lib/heartbeat.sh — Heartbeat monitoring, dynamic timeouts, portable timeout
# Extracted from orchestrate.sh (v8.19.0 heartbeat + v7.16.0 timeout)
# ═══════════════════════════════════════════════════════════════════════════════

# Opt-in lifecycle event stream — no-op unless OCTO_EVENT_LOG is set. Sourced
# guarded so heartbeat stays usable even if events.sh is absent.
_octo_heartbeat_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${_octo_heartbeat_lib_dir}/events.sh" 2>/dev/null || true

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
    # Antigravity: cap at 90s for probe tasks
    # Claude-sonnet: consistently 35-46s, cap at 60s for probe tasks
    local provider_cap=""
    case "$agent_type" in
        codex*)     provider_cap=150 ;;
        gemini*|agy*|antigravity) provider_cap=90 ;;
        qwen*)      provider_cap=90 ;;   # oco-dar: Gemini-CLI fork — same profile; cap auth-hang risk
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


# Run an external command under GNU timeout while preserving the caller process
# group. timeout --foreground intentionally stops managing a separate command
# process group, so this wrapper owns descendant cleanup on TERM/INT/HUP without
# ever signalling the caller's PGID.
_run_with_timeout_preserving_process_group() {
    local timeout_bin="$1"
    local timeout_secs="$2"
    shift 2

    "$timeout_bin" --foreground "$timeout_secs" bash -c '
        set +e
        _octo_collect_descendants() {
            local parent="$1" child
            while IFS= read -r child; do
                child="${child//[[:space:]]/}"
                [[ -n "$child" ]] || continue
                _octo_collect_descendants "$child"
                _octo_descendants+=("$child")
            done < <(ps -eo pid=,ppid= | while read -r pid ppid; do [[ "$ppid" == "$parent" ]] && echo "$pid"; done)
        }
        _octo_cleanup_descendants() {
            _octo_descendants=()
            _octo_collect_descendants "$child_pid"
            if ((${#_octo_descendants[@]})); then
                kill -TERM "${_octo_descendants[@]}" 2>/dev/null || true
            fi
            kill -TERM "$child_pid" 2>/dev/null || true

            # Match timeout -k 10 semantics: give the provider subtree the full
            # 10-second TERM grace period before escalating remaining processes.
            for _octo_i in $(seq 1 100); do
                _octo_any_alive=false
                kill -0 "$child_pid" 2>/dev/null && _octo_any_alive=true
                for _octo_pid in "${_octo_descendants[@]}"; do
                    if kill -0 "$_octo_pid" 2>/dev/null; then
                        _octo_any_alive=true
                        break
                    fi
                done
                [[ "$_octo_any_alive" == "false" ]] && break
                sleep 0.1
            done

            _octo_descendants=()
            _octo_collect_descendants "$child_pid"
            if ((${#_octo_descendants[@]})); then
                kill -KILL "${_octo_descendants[@]}" 2>/dev/null || true
            fi
            kill -KILL "$child_pid" 2>/dev/null || true
            wait "$child_pid" 2>/dev/null || true
        }
        _octo_on_signal() {
            trap - TERM INT HUP
            _octo_cleanup_descendants
            exit 143
        }
        trap _octo_on_signal TERM INT HUP
        "$@" <&0 &
        child_pid=$!
        wait "$child_pid"
        status=$?
        trap - TERM INT HUP
        exit "$status"
    ' bash "$@"
}

# Snapshot a process tree before signalling it. A parent can exit and reparent
# its descendants immediately after TERM, so discovering children after the
# root is gone is too late for reliable cleanup.
_octo_timeout_process_tree_depth_first() {
    local root_pid="$1" child_pid process_started
    while IFS= read -r child_pid; do
        child_pid="${child_pid//[[:space:]]/}"
        [[ "$child_pid" =~ ^[1-9][0-9]*$ ]] || continue
        _octo_timeout_process_tree_depth_first "$child_pid"
    done < <(ps -eo pid=,ppid= 2>/dev/null | awk -v parent="$root_pid" '$2 == parent { print $1 }')
    process_started="$(ps -o lstart= -p "$root_pid" 2>/dev/null)" || return 0
    printf '%s\t%s\n' "$root_pid" "$process_started"
}

_octo_timeout_pid_is_running() {
    local pid="$1" expected_started="${2:-}" process_stat process_started
    kill -0 "$pid" 2>/dev/null || return 1
    process_stat="$(ps -o stat= -p "$pid" 2>/dev/null)" || return 1
    [[ "$process_stat" != *Z* ]] || return 1
    [[ -z "$expected_started" ]] && return 0
    process_started="$(ps -o lstart= -p "$pid" 2>/dev/null)" || return 1
    [[ "$process_started" == "$expected_started" ]]
}

_octo_timeout_signal_snapshot() {
    local signal_name="$1" process_tree="$2" target_pid process_started
    while IFS=$'\t' read -r target_pid process_started; do
        [[ "$target_pid" =~ ^[1-9][0-9]*$ && "$target_pid" != "1" ]] || continue
        _octo_timeout_pid_is_running "$target_pid" "$process_started" || continue
        kill -"$signal_name" "$target_pid" 2>/dev/null || true
    done <<< "$process_tree"
}

_octo_timeout_mark_snapshot() {
    local marker="$1" process_tree="$2"
    [[ -n "$process_tree" ]] || return 0
    printf '%s\n' "$process_tree" > "$marker"
}

# Portable timeout function (works on macOS and Linux)
# Prefers system timeout commands, falls back to manual implementation
run_with_timeout() {
    local timeout_secs="$1"
    shift

    local exit_code
    local _octo_cmd_label="${1:-unknown}"

    if declare -f octo_event_emit >/dev/null 2>&1; then
        octo_event_emit "dispatch.start" command="$_octo_cmd_label" timeout="$timeout_secs" || true
    fi

    # timeout_secs=0 means no absolute timeout. Callers that choose it must set
    # OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED to document the external heartbeat,
    # stall, or workflow-level watchdog responsible for recovery.
    if [[ "$timeout_secs" =~ ^[0-9]+$ ]] && [[ "$timeout_secs" -eq 0 ]]; then
        "$@"
        exit_code=$?
        if declare -f octo_event_emit >/dev/null 2>&1; then
            local _octo_outcome="ok"
            [[ $exit_code -eq 0 ]] || _octo_outcome="error"
            octo_event_emit "dispatch.end" command="$_octo_cmd_label" exit_code="$exit_code" outcome="$_octo_outcome" timeout="none" || true
        fi
        return "$exit_code"
    fi

    # v9.20.1: Detect if command is a shell function (e.g. perplexity_execute,
    # openrouter_execute). External timeout/gtimeout can only exec binaries —
    # shell functions require the in-process fallback path. (#255)
    local _cmd_is_function=false
    if [[ "$(type -t "$1" 2>/dev/null)" == "function" ]]; then
        _cmd_is_function=true
    fi

    # Use gtimeout (GNU) or timeout if available AND command is an external binary.
    # oco-dar: `-k 10` escalates to SIGKILL 10s after the initial SIGTERM. A
    # provider that catches SIGTERM and stalls (e.g. node mid-OAuth device-flow)
    # would otherwise outlive the timeout — that is exactly how an expired-token
    # qwen probe hung ~10min instead of dying at the per-agent cap.
    if [[ "$_cmd_is_function" == "false" ]] && command -v gtimeout &>/dev/null; then
        if [[ "${OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP:-false}" == "true" ]]; then
            _run_with_timeout_preserving_process_group gtimeout "$timeout_secs" "$@"
        else
            gtimeout -k 10 "$timeout_secs" "$@"
        fi
        exit_code=$?
    elif [[ "$_cmd_is_function" == "false" ]] && command -v timeout &>/dev/null; then
        if [[ "${OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP:-false}" == "true" ]]; then
            _run_with_timeout_preserving_process_group timeout "$timeout_secs" "$@"
        else
            timeout -k 10 "$timeout_secs" "$@"
        fi
        exit_code=$?
    else
        # Fallback with proper cleanup (also used for shell functions).
        # `<&0` explicitly inherits stdin from the caller: non-interactive bash
        # otherwise redirects background-job stdin to /dev/null, which starves
        # shell-function providers (perplexity_execute, openrouter_execute)
        # that read their prompt from stdin. See issue #307.
        local cmd_pid monitor_pid timeout_marker process_tree=""

        "$@" <&0 &
        cmd_pid=$!

        timeout_marker="$(umask 077 && mktemp "${TMPDIR:-/tmp}/octo-timeout.XXXXXX")" || {
            kill -KILL "$cmd_pid" 2>/dev/null || true
            wait "$cmd_pid" 2>/dev/null || true
            return 1
        }

        # Snapshot before TERM: children may be reparented as soon as the root
        # exits. Persist the frozen PID set before signalling so the parent can
        # finish cleanup even if it races with and stops this monitor.
        (
            sleep "$timeout_secs"
            process_tree="$(_octo_timeout_process_tree_depth_first "$cmd_pid")"
            _octo_timeout_mark_snapshot "$timeout_marker" "$process_tree"
            _octo_timeout_signal_snapshot TERM "$process_tree"

            local grace_tick target_pid process_started any_running
            for ((grace_tick=0; grace_tick<100; grace_tick++)); do
                any_running=false
                while IFS=$'\t' read -r target_pid process_started; do
                    if _octo_timeout_pid_is_running "$target_pid" "$process_started"; then
                        any_running=true
                        break
                    fi
                done <<< "$process_tree"
                [[ "$any_running" == "false" ]] && break
                sleep 0.1
            done

            _octo_timeout_signal_snapshot KILL "$process_tree"
        # Redirect the monitor's stdout away from the caller's: on the shell-
        # function path this subshell inherits the pipe into spawn_agent's `tee`,
        # and its `sleep` child is orphaned (reparented) when the monitor is
        # killed on a normal completion — an orphan holding the pipe's write end
        # keeps `tee` from ever seeing EOF, so the pipeline blocks for the full
        # timeout even though the command already produced its output.
        ) >/dev/null 2>&1 &
        monitor_pid=$!

        if wait "$cmd_pid" 2>/dev/null; then
            exit_code=0
        else
            exit_code=$?
        fi

        # Stop and join the monitor before examining the marker to close the
        # timeout-boundary race. A non-empty marker contains the frozen process
        # tree; sweep it from the parent too in case the monitor was interrupted
        # during its TERM grace period. Normal completions leave it empty.
        # `kill`/`wait` on a monitor that already exited on its own (race with its
        # sleep) return non-zero — under `set -e` that would kill this function (and
        # the seat's already-captured output with it) after the provider call
        # succeeded. Same class as the subshell kill fixed in #336. (#738)
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
        if [[ -s "$timeout_marker" ]]; then
            process_tree="$(< "$timeout_marker")"
            _octo_timeout_signal_snapshot KILL "$process_tree"
            exit_code=124
        fi
        rm -f "$timeout_marker"
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
        if declare -f octo_event_emit >/dev/null 2>&1; then
            octo_event_emit "dispatch.timeout" command="$_octo_cmd_label" timeout="$timeout_secs" exit_code="$exit_code" || true
        fi
        return 124
    fi

    if declare -f octo_event_emit >/dev/null 2>&1; then
        local _octo_outcome="ok"
        [[ $exit_code -eq 0 ]] || _octo_outcome="error"
        octo_event_emit "dispatch.end" command="$_octo_cmd_label" exit_code="$exit_code" outcome="$_octo_outcome" || true
    fi

    return $exit_code
}

# Capture provider stdin/stdout through files rather than a tee pipeline.
# Provider CLIs may spawn hooks or helpers that outlive the main process while
# retaining stdout. If stdout is a pipe, tee never receives EOF and the
# completed provider remains stuck until the fleet watchdog fires (#892).
octopus_capture_provider_output() {
    local prompt="$1"
    local timeout_secs="$2"
    local temp_input_hint="$3"
    local temp_input=""
    local raw_output="$4"
    local temp_errors="$5"
    shift 5

    temp_input="$(umask 077 && mktemp "${temp_input_hint}.XXXXXX")" || return 1
    if ! printf '%s' "$prompt" > "$temp_input"; then
        rm -f "$temp_input"
        return 1
    fi

    local exit_code=0
    if OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="spawn-agent-heartbeat" \
        OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP="true" \
        run_with_timeout "$timeout_secs" "$@" < "$temp_input" > "$raw_output" 2> "$temp_errors"; then
        exit_code=0
    else
        exit_code=$?
    fi

    rm -f "$temp_input"
    return "$exit_code"
}
