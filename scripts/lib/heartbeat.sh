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


_octo_timeout_signal_status() {
    case "$1" in
        HUP)  printf '%s\n' 129 ;;
        INT)  printf '%s\n' 130 ;;
        TERM) printf '%s\n' 143 ;;
        *)    printf '%s\n' 1 ;;
    esac
}

_octo_timeout_restore_trap() {
    local signal_name="$1" saved_trap="$2"
    if [[ -n "$saved_trap" ]]; then
        eval "$saved_trap"
    else
        trap - "$signal_name"
    fi
}

_octo_timeout_restore_signal_traps() {
    _octo_timeout_restore_trap INT "$1"
    _octo_timeout_restore_trap TERM "$2"
    _octo_timeout_restore_trap HUP "$3"
}

# Ask a direct child to signal its actual parent. Bash 3.2 has no BASHPID, and
# $$ intentionally remains the top-level shell PID inside subshells, so neither
# is safe when this library itself runs in a background shell.
_octo_timeout_redeliver_signal() {
    /bin/sh -c 'kill -s "$1" "$PPID"' octo-signal "$1"
}

_octo_timeout_process_group_exists() {
    local process_group="$1"
    [[ "$process_group" =~ ^[1-9][0-9]*$ && "$process_group" != "1" ]] || return 1
    kill -0 -- "-$process_group" 2>/dev/null
}

_octo_timeout_job_is_running() {
    local expected_pid="$1" job_pid
    while IFS= read -r job_pid; do
        [[ "$job_pid" == "$expected_pid" ]] && return 0
    done < <(jobs -pr 2>/dev/null)
    return 1
}

_octo_timeout_stop_process_group() {
    local process_group="$1" initial_signal="$2" allow_term_grace="$3"
    local grace_deadline kill_grace="${OCTOPUS_TIMEOUT_KILL_GRACE:-10}"
    [[ "$process_group" =~ ^[1-9][0-9]*$ && "$process_group" != "1" ]] || return 0
    [[ "$kill_grace" =~ ^[0-9]+$ && "$kill_grace" -le 10 ]] || kill_grace=10

    kill -"$initial_signal" -- "-$process_group" 2>/dev/null || true
    if [[ "$allow_term_grace" == "true" && "$kill_grace" -gt 0 ]]; then
        # Match timeout -k 10: allow the provider group ten seconds to perform
        # normal TERM cleanup before forcing out resistant descendants.
        # Bound the grace by Bash's built-in wall clock. Counting external sleep
        # processes can stretch a nominal ten-second grace on a busy macOS runner.
        grace_deadline=$((SECONDS + kill_grace))
        while (( SECONDS < grace_deadline )); do
            _octo_timeout_process_group_exists "$process_group" || break
            sleep 0.1
        done
    else
        # An interrupted caller is already unwinding. Give ordinary handlers a
        # scheduling turn, then force out the remaining provider process group.
        sleep 0.1
    fi
    kill -KILL -- "-$process_group" 2>/dev/null || true
}

_octo_timeout_supervisor_handle_signal() {
    local signal_name="$1" exit_status initial_signal
    exit_status="$(_octo_timeout_signal_status "$signal_name")"
    initial_signal="$signal_name"

    # Prevent nested signals from interrupting cleanup. Reap the timer first to
    # suppress Bash job-status output, then terminate the private provider PGID.
    trap '' TERM INT HUP
    if [[ "${timer_pid:-}" =~ ^[1-9][0-9]*$ ]]; then
        kill -KILL -- "-$timer_pid" 2>/dev/null || true
        wait "$timer_pid" 2>/dev/null || true
    fi
    if [[ "${provider_pid:-}" =~ ^[1-9][0-9]*$ ]]; then
        _octo_timeout_stop_process_group "$provider_pid" "$initial_signal" false
        wait "$provider_pid" 2>/dev/null || true
    fi
    exit "$exit_status"
}

_octo_timeout_timer() {
    /bin/sleep "$1"
}

# Bash 3.2/macOS-compatible timeout supervisor. Monitor mode gives the provider
# wrapper a private process group; monitor mode is disabled again inside that
# wrapper so its full descendant tree remains in the same group. The wrapper PID
# stays an unreaped child until cleanup completes, preventing PGID reuse even if
# process metadata cannot be read with ps.
_octo_timeout_supervisor() {
    local timeout_secs="$1"
    shift
    local provider_pid="" timer_pid="" provider_status=0 timer_status=0
    local timer_enabled=true
    [[ "$timeout_secs" -eq 0 ]] && timer_enabled=false

    set -m
    trap '_octo_timeout_supervisor_handle_signal TERM' TERM
    trap '_octo_timeout_supervisor_handle_signal HUP' HUP

    (
        set +m
        "$@" <&0
    ) <&0 &
    provider_pid=$!

    # Keep the timer as a supervised job instead of delivering an asynchronous
    # signal. Bash 3.2 lacks wait -n, so the loop below polls both child jobs and
    # can distinguish provider completion, deadline expiry, and timer failure.
    if [[ "$timer_enabled" == true ]]; then
        (
            set +m
            _octo_timeout_timer "$timeout_secs"
        ) &
        timer_pid=$!
    fi
    # The jobs retain their private groups after monitor mode is disabled, and
    # Bash no longer prints asynchronous "Done" notices into provider output.
    set +m

    # Keep both process-group leaders unreaped until a winner is known. This
    # preserves their PGID identities while descendant cleanup is still needed.
    while :; do
        local provider_running=true timer_running=true
        _octo_timeout_job_is_running "$provider_pid" || provider_running=false
        if [[ "$timer_enabled" == true ]]; then
            _octo_timeout_job_is_running "$timer_pid" || timer_running=false
        fi

        if [[ "$provider_running" == false ]]; then
            # Reap an already-completed timer before choosing the provider path.
            # A failed timer is an infrastructure failure even if the provider
            # also finished; a successful deadline tie deliberately defers to
            # the provider's result. Both PGID leaders remain unreaped until all
            # descendants have been contained.
            trap '' TERM INT HUP
            if [[ "$timer_enabled" == true ]]; then
                kill -KILL -- "-$timer_pid" 2>/dev/null || true
                if wait "$timer_pid" 2>/dev/null; then
                    timer_status=0
                else
                    timer_status=$?
                fi
            fi
            kill -KILL -- "-$provider_pid" 2>/dev/null || true
            if wait "$provider_pid" 2>/dev/null; then
                provider_status=0
            else
                provider_status=$?
            fi
            trap - TERM INT HUP
            set +m
            if [[ "$timer_enabled" == true && "$timer_running" == false && "$timer_status" -ne 0 ]]; then
                if declare -f log >/dev/null 2>&1; then
                    log ERROR "Portable timeout timer failed with status $timer_status"
                else
                    printf 'ERROR: portable timeout timer failed with status %s\n' "$timer_status" >&2
                fi
                return 125
            fi
            return "$provider_status"
        fi

        if [[ "$timer_enabled" == true && "$timer_running" == false ]]; then
            trap '' TERM INT HUP
            kill -KILL -- "-$timer_pid" 2>/dev/null || true
            if wait "$timer_pid" 2>/dev/null; then
                timer_status=0
            else
                timer_status=$?
            fi
            if [[ "$timer_status" -eq 0 ]]; then
                _octo_timeout_stop_process_group "$provider_pid" TERM true
                wait "$provider_pid" 2>/dev/null || true
                trap - TERM INT HUP
                set +m
                return 124
            fi

            if declare -f log >/dev/null 2>&1; then
                log ERROR "Portable timeout timer failed with status $timer_status"
            else
                printf 'ERROR: portable timeout timer failed with status %s\n' "$timer_status" >&2
            fi
            _octo_timeout_stop_process_group "$provider_pid" TERM false
            wait "$provider_pid" 2>/dev/null || true
            trap - TERM INT HUP
            set +m
            return 125
        fi
        /bin/sleep 0.02
    done
}

# Normalize a decimal timeout without evaluating untrusted digits as shell
# arithmetic. The portable maximum is 1,073,741,823 seconds: doubling it for
# timeout guidance remains within signed 32-bit arithmetic used by Bash 3.2.
_octo_timeout_normalize_seconds() {
    local value="$1" max_seconds="1073741823" LC_ALL=C
    case "$value" in
        ""|*[!0-9]*) return 1 ;;
    esac
    while [[ "${#value}" -gt 1 && "${value#0}" != "$value" ]]; do
        value="${value#0}"
    done
    # Equal-length normalized decimal strings compare by magnitude lexically;
    # arithmetic here could overflow on the Bash 3.2 platforms this guards.
    # shellcheck disable=SC2071
    if [[ "${#value}" -gt "${#max_seconds}" ]] ||
       { [[ "${#value}" -eq "${#max_seconds}" ]] && [[ "$value" > "$max_seconds" ]]; }; then
        return 1
    fi
    printf '%s\n' "$value"
}

_octo_timeout_handle_caller_signal() {
    local signal_name="$1"
    _octo_timeout_interrupted_status="$(_octo_timeout_signal_status "$signal_name")"

    trap '' TERM INT HUP
    if [[ "${_octo_timeout_supervisor_pid:-}" =~ ^[1-9][0-9]*$ ]] &&
       _octo_timeout_job_is_running "$_octo_timeout_supervisor_pid"; then
        # TERM is always actionable for an asynchronous Bash child; INT may be
        # inherited as ignored when the caller has job control disabled. The
        # jobs check proves this PID is still our live child before signalling.
        kill -TERM "$_octo_timeout_supervisor_pid" 2>/dev/null || true
        wait "$_octo_timeout_supervisor_pid" 2>/dev/null || true
    fi
    _octo_timeout_restore_signal_traps \
        "$_octo_timeout_previous_int_trap" \
        "$_octo_timeout_previous_term_trap" \
        "$_octo_timeout_previous_hup_trap"
    _octo_timeout_redeliver_signal "$signal_name"
    return "$_octo_timeout_interrupted_status"
}

_octo_run_portable_supervisor() {
    local timeout_secs="$1"
    shift
    local _octo_timeout_previous_int_trap _octo_timeout_previous_term_trap
    local _octo_timeout_previous_hup_trap _octo_timeout_supervisor_pid=""
    local _octo_timeout_interrupted_status=0

    _octo_timeout_previous_int_trap="$(trap -p INT)"
    _octo_timeout_previous_term_trap="$(trap -p TERM)"
    _octo_timeout_previous_hup_trap="$(trap -p HUP)"
    trap '_octo_timeout_handle_caller_signal INT' INT
    trap '_octo_timeout_handle_caller_signal TERM' TERM
    trap '_octo_timeout_handle_caller_signal HUP' HUP

    _octo_timeout_supervisor "$timeout_secs" "$@" <&0 &
    _octo_timeout_supervisor_pid=$!
    if [[ "$_octo_timeout_interrupted_status" -ne 0 ]]; then
        kill -TERM "$_octo_timeout_supervisor_pid" 2>/dev/null || true
        wait "$_octo_timeout_supervisor_pid" 2>/dev/null || true
        _octo_portable_supervisor_interrupted_status="$_octo_timeout_interrupted_status"
        return "$_octo_timeout_interrupted_status"
    fi

    local exit_code=0
    if wait "$_octo_timeout_supervisor_pid" 2>/dev/null; then
        exit_code=0
    else
        exit_code=$?
    fi

    if [[ "$_octo_timeout_interrupted_status" -ne 0 ]]; then
        _octo_portable_supervisor_interrupted_status="$_octo_timeout_interrupted_status"
        return "$_octo_timeout_interrupted_status"
    fi
    _octo_timeout_restore_signal_traps \
        "$_octo_timeout_previous_int_trap" \
        "$_octo_timeout_previous_term_trap" \
        "$_octo_timeout_previous_hup_trap"
    _octo_portable_supervisor_interrupted_status=0
    return "$exit_code"
}

# Portable timeout function (works on macOS and Linux).
# Prefers system timeout commands unless the internal --portable-supervisor
# option is requested by a caller that must process signals while it waits.
run_with_timeout() {
    local force_portable_supervisor=false
    if [[ "${1:-}" == "--portable-supervisor" ]]; then
        force_portable_supervisor=true
        shift
    fi
    local timeout_input="${1:-}" timeout_secs
    shift

    if ! timeout_secs="$(_octo_timeout_normalize_seconds "$timeout_input")"; then
        if declare -f log >/dev/null 2>&1; then
            log ERROR "Invalid timeout '${timeout_input:-empty}': expected 0..1073741823 seconds"
        else
            printf 'ERROR: invalid timeout %s; expected 0..1073741823 seconds\n' \
                "${timeout_input:-empty}" >&2
        fi
        return 2
    fi

    # Preserving the caller's process group requires our private-process-group
    # supervisor. GNU timeout --foreground does not provide containment, and a
    # process-table reconstruction is both racy and capable of delaying cleanup.
    if [[ "${OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP:-false}" == "true" ]]; then
        force_portable_supervisor=true
    fi

    # Automatic Premium peer receipts need a launch acknowledgement that is
    # established after this function's caller has installed its output and
    # error redirections, but before any supervisor or provider process starts.
    # If the acknowledgement cannot be written, do not launch an unaccounted
    # provider call.
    if [[ -n "${OCTOPUS_AUTO_PEER_DISPATCH_MARKER:-}" ]]; then
        if ! (umask 077; printf '%s\n' started > "$OCTOPUS_AUTO_PEER_DISPATCH_MARKER") 2>/dev/null; then
            if declare -f log >/dev/null 2>&1; then
                log WARN "Automatic Premium peer dispatch start could not be recorded; refusing to launch"
            else
                printf '%s\n' "WARN: automatic Premium peer dispatch start could not be recorded; refusing to launch" >&2
            fi
            return 74
        fi
    fi

    local exit_code
    local _octo_portable_supervisor_interrupted_status=0
    local _octo_cmd_label="${1:-unknown}"

    if declare -f octo_event_emit >/dev/null 2>&1; then
        octo_event_emit "dispatch.start" command="$_octo_cmd_label" timeout="$timeout_secs" || true
    fi

    # timeout_secs=0 means no absolute timeout. Callers that choose it must set
    # OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED to document the external heartbeat,
    # stall, or workflow-level watchdog responsible for recovery.
    if [[ "$timeout_secs" =~ ^[0-9]+$ ]] && [[ "$timeout_secs" -eq 0 ]]; then
        if [[ "$force_portable_supervisor" == "true" ]]; then
            if _octo_run_portable_supervisor 0 "$@"; then
                exit_code=0
            else
                exit_code=$?
            fi
        else
            "$@"
            exit_code=$?
        fi
        if [[ "$_octo_portable_supervisor_interrupted_status" -ne 0 ]]; then
            return "$_octo_portable_supervisor_interrupted_status"
        fi
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
    if [[ "$force_portable_supervisor" == "false" && "$_cmd_is_function" == "false" ]] &&
       command -v gtimeout &>/dev/null; then
        gtimeout -k 10 "$timeout_secs" "$@"
        exit_code=$?
    elif [[ "$force_portable_supervisor" == "false" && "$_cmd_is_function" == "false" ]] &&
         command -v timeout &>/dev/null; then
        timeout -k 10 "$timeout_secs" "$@"
        exit_code=$?
    else
        # The Bash 3.2 fallback runs a supervisor asynchronously so this shell
        # can trap interruption while waiting. The provider itself receives the
        # caller's stdin through the private process-group wrapper.
        if _octo_run_portable_supervisor "$timeout_secs" "$@"; then
            exit_code=0
        else
            exit_code=$?
        fi
    fi

    if [[ "$_octo_portable_supervisor_interrupted_status" -ne 0 ]]; then
        return "$_octo_portable_supervisor_interrupted_status"
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

_octo_capture_file_signature() {
    local path="$1"
    [[ -e "$path" ]] || { printf '%s\n' missing; return 0; }
    if stat -f '%z:%m' "$path" >/dev/null 2>&1; then
        stat -f '%z:%m' "$path"
    elif stat -c '%s:%Y' "$path" >/dev/null 2>&1; then
        stat -c '%s:%Y' "$path"
    else
        printf '%s:%s\n' "$(wc -c < "$path" 2>/dev/null || echo 0)" unknown
    fi
}

_octo_capture_worktree_fingerprint() {
    local worktree="${1:-}"
    [[ -n "$worktree" && -d "$worktree" ]] || { printf '%s\n' none; return 0; }
    command -v git >/dev/null 2>&1 || { printf '%s\n' none; return 0; }

    # Hash status plus size/mtime metadata for every changed or untracked file.
    # This notices continued writes to an already-modified path without hashing
    # entire file contents or large binary diffs on every poll.
    _octo_capture_worktree_state() {
        git -C "$worktree" status --porcelain -uall 2>/dev/null || true
        {
            git -C "$worktree" diff --name-only -z 2>/dev/null || true
            git -C "$worktree" diff --cached --name-only -z 2>/dev/null || true
            git -C "$worktree" ls-files --others --exclude-standard -z 2>/dev/null || true
        } | while IFS= read -r -d '' rel; do
            [[ -n "$rel" ]] || continue
            printf 'path=%s;' "$rel"
            _octo_capture_file_signature "$worktree/$rel"
        done
    }

    if command -v sha256sum >/dev/null 2>&1; then
        _octo_capture_worktree_state | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        _octo_capture_worktree_state | shasum -a 256 | awk '{print $1}'
    else
        printf '%s\n' unavailable
    fi
    unset -f _octo_capture_worktree_state 2>/dev/null || true
}

_octo_capture_activity_signature() {
    local raw_output="$1" temp_errors="$2" worktree="${3:-}"
    printf 'out=%s;err=%s;tree=%s\n' \
        "$(_octo_capture_file_signature "$raw_output")" \
        "$(_octo_capture_file_signature "$temp_errors")" \
        "$(_octo_capture_worktree_fingerprint "$worktree")"
}

_octo_capture_provider_with_stall_watchdog() {
    local timeout_secs="$1" stall_window="$2" poll_secs="$3"
    local temp_input="$4" raw_output="$5" temp_errors="$6" worktree="${7:-}"
    shift 7
    local rc_file capture_pid child_rc=125
    local last_signature current_signature last_progress now next_probe
    local stalled=false grace_deadline

    rc_file="$(umask 077 && mktemp "${temp_input}.rc.XXXXXX")" || return 1
    (
        local provider_rc=0
        if OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="provider-stall-watchdog" \
            OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP="true" \
            run_with_timeout --portable-supervisor "$timeout_secs" "$@" \
                < "$temp_input" > "$raw_output" 2> "$temp_errors"; then
            provider_rc=0
        else
            provider_rc=$?
        fi
        printf '%s\n' "$provider_rc" > "$rc_file"
    ) &
    capture_pid=$!

    last_signature="$(_octo_capture_activity_signature "$raw_output" "$temp_errors" "$worktree")"
    last_progress="$(date +%s)"
    next_probe=$((last_progress + poll_secs))

    while kill -0 "$capture_pid" 2>/dev/null; do
        [[ -s "$rc_file" ]] && break
        sleep 1
        now="$(date +%s)"
        if [[ "$now" -ge "$next_probe" ]]; then
            current_signature="$(_octo_capture_activity_signature "$raw_output" "$temp_errors" "$worktree")"
            if [[ "$current_signature" != "$last_signature" ]]; then
                last_signature="$current_signature"
                last_progress="$now"
                if declare -f log >/dev/null 2>&1; then
                    log DEBUG "Provider stall watchdog: observable progress detected"
                fi
            fi
            next_probe=$((now + poll_secs))
        fi
        if [[ $((now - last_progress)) -ge "$stall_window" ]]; then
            stalled=true
            if declare -f log >/dev/null 2>&1; then
                log WARN "Provider stall watchdog: no observable progress for ${stall_window}s; stopping provider"
            fi
            if declare -f octo_event_emit >/dev/null 2>&1; then
                octo_event_emit "dispatch.stalled" command="${1:-unknown}" stall_window="$stall_window" exit_code=76 || true
            fi
            kill -TERM "$capture_pid" 2>/dev/null || true
            grace_deadline=$((SECONDS + 12))
            while kill -0 "$capture_pid" 2>/dev/null && (( SECONDS < grace_deadline )); do
                sleep 0.2
            done
            kill -KILL "$capture_pid" 2>/dev/null || true
            break
        fi
    done

    wait "$capture_pid" 2>/dev/null || true
    if [[ "$stalled" == true ]]; then
        rm -f "$rc_file"
        return 76
    fi
    if [[ -s "$rc_file" ]]; then
        child_rc="$(cat "$rc_file" 2>/dev/null || echo 125)"
    fi
    rm -f "$rc_file"
    [[ "$child_rc" =~ ^[0-9]+$ ]] || child_rc=125
    return "$child_rc"
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

    local stall_window="${OCTOPUS_PROVIDER_STALL_WINDOW:-0}"
    local stall_poll_secs="${OCTOPUS_PROVIDER_STALL_POLL_SECS:-30}"
    local stall_worktree="${OCTOPUS_PROVIDER_STALL_WORKTREE:-}"
    if ! stall_window="$(_octo_timeout_normalize_seconds "$stall_window")"; then
        rm -f "$temp_input"
        return 2
    fi
    if ! stall_poll_secs="$(_octo_timeout_normalize_seconds "$stall_poll_secs")" \
       || [[ "$stall_poll_secs" -eq 0 ]]; then
        rm -f "$temp_input"
        return 2
    fi

    local exit_code=0
    if [[ "$stall_window" -gt 0 ]]; then
        if _octo_capture_provider_with_stall_watchdog \
            "$timeout_secs" "$stall_window" "$stall_poll_secs" \
            "$temp_input" "$raw_output" "$temp_errors" "$stall_worktree" "$@"; then
            exit_code=0
        else
            exit_code=$?
        fi
    elif OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="spawn-agent-heartbeat" \
        OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP="true" \
        run_with_timeout "$timeout_secs" "$@" < "$temp_input" > "$raw_output" 2> "$temp_errors"; then
        exit_code=0
    else
        exit_code=$?
    fi

    rm -f "$temp_input"
    return "$exit_code"
}
