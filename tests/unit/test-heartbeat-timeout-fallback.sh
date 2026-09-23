#!/bin/bash
# Regression coverage for the portable run_with_timeout fallback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
log() { :; }
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"

test_suite "Heartbeat portable timeout fallback"

_wait_for_nonempty_file() {
    local path="$1" attempt
    for ((attempt=0; attempt<100; attempt++)); do
        [[ -s "$path" ]] && return 0
        sleep 0.05
    done
    return 1
}

_pid_is_live() {
    local pid="$1" process_stat
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    process_stat="$(/bin/ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$process_stat" && "$process_stat" != Z* ]]
}

test_timeout_signals_root_without_ps() {
    test_case "portable timeout signals and reaps its root when ps blocks"
    local target="$TEST_TMP_DIR/timeout-root.sh"
    local pid_file="$TEST_TMP_DIR/timeout-root.pid"
    local rc=0 elapsed_seconds target_pid="" alive=false

    cat > "$target" <<'EOF'
#!/bin/bash
printf '%s\n' "$$" > "$1"
exec /bin/sleep 4
EOF
    chmod +x "$target"

    # Force the in-process path and simulate blocked process enumeration. The
    # deadline and provider PGID cleanup must not depend on ps returning.
    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }
    ps() { /bin/sleep 30; }

    SECONDS=0
    run_with_timeout 1 "$target" "$pid_file" >/dev/null 2>&1 || rc=$?
    elapsed_seconds=$SECONDS

    unset -f command ps
    [[ -s "$pid_file" ]] && target_pid="$(< "$pid_file")"
    if [[ -n "$target_pid" ]] && kill -0 "$target_pid" 2>/dev/null; then
        alive=true
        kill -KILL "$target_pid" 2>/dev/null || true
    fi

    if [[ "$rc" -eq 124 && -n "$target_pid" && "$alive" == false && \
          "$elapsed_seconds" -le 8 ]]; then
        test_pass
    else
        test_fail "expected rc=124, a reaped root, and completion within 8s; got rc=$rc pid=${target_pid:-missing} alive=$alive elapsed=${elapsed_seconds}s"
    fi
}

test_supervisor_isolates_provider_group_without_mutating_caller() {
    test_case "portable supervisor isolates the provider PGID without changing caller job control"
    local caller_pgid provider_pgid monitor_before monitor_after

    caller_pgid="$(/bin/ps -o pgid= -p "$$" | tr -d '[:space:]')"
    monitor_before="$(set -o | awk '$1 == "monitor" { print $2 }')"
    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }

    provider_pgid="$(run_with_timeout 2 /bin/sh -c '/bin/ps -o pgid= -p $$ | tr -d "[:space:]"')"
    monitor_after="$(set -o | awk '$1 == "monitor" { print $2 }')"
    unset -f command

    if [[ "$provider_pgid" =~ ^[1-9][0-9]*$ && "$provider_pgid" != "$caller_pgid" &&
          "$monitor_before" == "$monitor_after" ]]; then
        test_pass
    else
        test_fail "expected private provider PGID and unchanged monitor state; got caller=$caller_pgid provider=${provider_pgid:-missing} monitor=$monitor_before->$monitor_after"
    fi
}

test_timeout_timer_does_not_depend_on_path_sleep() {
    test_case "portable timeout uses an absolute sleep under a restricted PATH"
    local rc=0 elapsed_seconds
    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }
    SECONDS=0
    PATH=/nonexistent run_with_timeout 2 /bin/sleep 1 >/dev/null 2>&1 || rc=$?
    elapsed_seconds=$SECONDS
    unset -f command
    if [[ "$rc" -eq 0 && "$elapsed_seconds" -ge 1 ]]; then
        test_pass
    else
        test_fail "expected rc=0 after at least 1s; got rc=$rc elapsed=${elapsed_seconds}s"
    fi
}

test_completed_timer_failure_outranks_provider_success() {
    test_case "completed timer failure outranks provider success and contains descendants"
    local original_job_check original_timer target child_file rc=0 child_pid="" child_alive=false
    target="$TEST_TMP_DIR/simultaneous-timer-failure-provider.sh"
    child_file="$TEST_TMP_DIR/simultaneous-timer-failure-child.pid"
    cat > "$target" <<'EOF'
#!/bin/bash
/bin/sh -c 'trap "" TERM; exec /bin/sleep 30' &
printf '%s\n' "$!" > "$1"
exit 0
EOF
    chmod +x "$target"

    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }

    original_job_check="$(declare -f _octo_timeout_job_is_running)"
    eval "${original_job_check/_octo_timeout_job_is_running/_octo_timeout_job_is_running_real}"
    original_timer="$(declare -f _octo_timeout_timer)"
    _octo_timeout_timer() { return 71; }
    _octo_timeout_job_is_running() {
        if [[ "${_octo_delayed_first_poll:-false}" == false ]]; then
            _octo_delayed_first_poll=true
            /bin/sleep 0.2
        fi
        _octo_timeout_job_is_running_real "$@"
    }
    run_with_timeout 30 "$target" "$child_file" >/dev/null 2>&1 || rc=$?
    unset -f command _octo_timeout_job_is_running _octo_timeout_job_is_running_real _octo_timeout_timer
    eval "$original_job_check"
    eval "$original_timer"

    [[ -s "$child_file" ]] && child_pid="$(< "$child_file")"
    /bin/sleep 0.2
    _pid_is_live "$child_pid" && child_alive=true
    if [[ "$child_alive" == true ]]; then kill -KILL "$child_pid" 2>/dev/null || true; fi

    if [[ "$rc" -eq 125 && -n "$child_pid" && "$child_alive" == false ]]; then
        test_pass
    else
        test_fail "expected timer rc=71 to yield rc=125 with no descendant; got rc=$rc child=${child_pid:-missing}/$child_alive"
    fi
}

test_simultaneous_successful_deadline_defers_to_provider_completion() {
    test_case "simultaneous successful deadline defers to provider completion"
    local original_job_check original_timer rc=0
    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }
    original_job_check="$(declare -f _octo_timeout_job_is_running)"
    eval "${original_job_check/_octo_timeout_job_is_running/_octo_timeout_job_is_running_real}"
    original_timer="$(declare -f _octo_timeout_timer)"
    _octo_timeout_timer() { return 0; }
    _octo_timeout_job_is_running() {
        if [[ "${_octo_delayed_first_poll:-false}" == false ]]; then
            _octo_delayed_first_poll=true
            /bin/sleep 0.2
        fi
        _octo_timeout_job_is_running_real "$@"
    }
    run_with_timeout 30 /bin/sh -c 'exit 7' >/dev/null 2>&1 || rc=$?
    unset -f command _octo_timeout_job_is_running _octo_timeout_job_is_running_real _octo_timeout_timer
    eval "$original_job_check"
    eval "$original_timer"
    if [[ "$rc" -eq 7 ]]; then
        test_pass
    else
        test_fail "expected provider completion rc=7 to win the successful deadline tie; got rc=$rc"
    fi
}

test_malformed_timeout_fails_before_provider_launch() {
    test_case "malformed timeout fails closed before launching the provider"
    local marker="$TEST_TMP_DIR/malformed-timeout-provider-ran" rc=0
    run_with_timeout not-a-timeout /bin/sh -c ': > "$1"' _ "$marker" >/dev/null 2>&1 || rc=$?
    if [[ "$rc" -eq 2 && ! -e "$marker" ]]; then
        test_pass
    else
        test_fail "expected rc=2 and no provider launch; got rc=$rc marker=$([[ -e "$marker" ]] && echo yes || echo no)"
    fi
}

test_timeout_overflow_fails_before_provider_launch() {
    test_case "portable timeout rejects decimal overflow before provider launch"
    local marker="$TEST_TMP_DIR/overflow-timeout-provider-ran" value rc
    for value in 1073741824 18446744073709551616 999999999999999999999999999999; do
        rc=0
        run_with_timeout "$value" /bin/sh -c ': > "$1"' _ "$marker" >/dev/null 2>&1 || rc=$?
        if [[ "$rc" -ne 2 || -e "$marker" ]]; then
            test_fail "expected rc=2 and no provider launch for $value; got rc=$rc marker=$([[ -e "$marker" ]] && echo yes || echo no)"
            return
        fi
    done
    test_pass
}

test_timeout_decimal_normalization_is_bounded() {
    test_case "timeout normalization strips leading zeros and accepts its maximum"
    local zero one maximum
    zero="$(_octo_timeout_normalize_seconds 0000000000)"
    one="$(_octo_timeout_normalize_seconds 0000000001)"
    maximum="$(_octo_timeout_normalize_seconds 1073741823)"
    if [[ "$zero" == 0 && "$one" == 1 && "$maximum" == 1073741823 ]]; then
        test_pass
    else
        test_fail "unexpected normalized values: zero='$zero' one='$one' maximum='$maximum'"
    fi
}

test_timer_failure_fails_closed_and_reaps_provider() {
    test_case "portable timer failure stops and reaps the provider"
    local target="$TEST_TMP_DIR/timer-failure-provider.sh"
    local pid_file="$TEST_TMP_DIR/timer-failure-provider.pid"
    local original_timer rc=0 elapsed_seconds provider_pid="" provider_alive=false

    cat > "$target" <<'EOF'
#!/bin/bash
printf '%s\n' "$$" > "$1"
exec /bin/sleep 30
EOF
    chmod +x "$target"

    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }
    original_timer="$(declare -f _octo_timeout_timer)"
    _octo_timeout_timer() { return 71; }

    SECONDS=0
    run_with_timeout 2 "$target" "$pid_file" >/dev/null 2>&1 || rc=$?
    elapsed_seconds=$SECONDS
    unset -f command _octo_timeout_timer
    eval "$original_timer"

    [[ -s "$pid_file" ]] && provider_pid="$(< "$pid_file")"
    sleep 0.2
    _pid_is_live "$provider_pid" && provider_alive=true
    if [[ "$provider_alive" == true ]]; then kill -KILL "$provider_pid" 2>/dev/null || true; fi

    if [[ "$rc" -eq 125 && "$provider_alive" == false && "$elapsed_seconds" -lt 2 ]]; then
        test_pass
    else
        test_fail "expected rc=125, dead provider, and immediate failure; got rc=$rc pid=${provider_pid:-missing} alive=$provider_alive elapsed=${elapsed_seconds}s"
    fi
}

test_timer_runtime_failure_fails_closed() {
    test_case "portable timer runtime failure cannot leave a provider unbounded"
    local original_timer rc=0 elapsed_seconds
    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }
    original_timer="$(declare -f _octo_timeout_timer)"
    _octo_timeout_timer() {
        /bin/sleep 0.1
        return 72
    }

    SECONDS=0
    run_with_timeout 30 /bin/sleep 30 >/dev/null 2>&1 || rc=$?
    elapsed_seconds=$SECONDS
    unset -f command _octo_timeout_timer
    eval "$original_timer"

    if [[ "$rc" -eq 125 && "$elapsed_seconds" -lt 2 ]]; then
        test_pass
    else
        test_fail "expected immediate rc=125 after timer runtime failure; got rc=$rc elapsed=${elapsed_seconds}s"
    fi
}

test_timeout_kills_term_resistant_descendant_without_ps() {
    test_case "portable timeout kills a TERM-resistant descendant without ps"
    local target="$TEST_TMP_DIR/timeout-tree.sh"
    local root_file="$TEST_TMP_DIR/timeout-tree-root.pid"
    local child_file="$TEST_TMP_DIR/timeout-tree-child.pid"
    local rc=0 elapsed_seconds root_pid="" child_pid=""
    local root_alive=false child_alive=false

    cat > "$target" <<'EOF'
#!/bin/bash
printf '%s\n' "$$" > "$1"
/bin/sh -c 'trap "" TERM; exec /bin/sleep 30' &
printf '%s\n' "$!" > "$2"
wait
EOF
    chmod +x "$target"

    command() {
        if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
            return 1
        fi
        builtin command "$@"
    }
    ps() { return 1; }

    SECONDS=0
    run_with_timeout 1 "$target" "$root_file" "$child_file" >/dev/null 2>&1 || rc=$?
    elapsed_seconds=$SECONDS

    unset -f command ps
    [[ -s "$root_file" ]] && root_pid="$(< "$root_file")"
    [[ -s "$child_file" ]] && child_pid="$(< "$child_file")"
    sleep 0.2
    _pid_is_live "$root_pid" && root_alive=true
    _pid_is_live "$child_pid" && child_alive=true

    if [[ "$root_alive" == true ]]; then kill -KILL "$root_pid" 2>/dev/null || true; fi
    if [[ "$child_alive" == true ]]; then kill -KILL "$child_pid" 2>/dev/null || true; fi

    if [[ "$rc" -eq 124 && -n "$root_pid" && -n "$child_pid" &&
          "$root_alive" == false && "$child_alive" == false &&
          "$elapsed_seconds" -ge 8 && "$elapsed_seconds" -le 30 ]]; then
        test_pass
    else
        test_fail "expected rc=124, a 10s TERM grace, and dead processes within 30s; got rc=$rc root=${root_pid:-missing}/$root_alive child=${child_pid:-missing}/$child_alive elapsed=${elapsed_seconds}s"
    fi
}

test_interruption_cleans_timeout_state_and_preserves_default_term() {
    test_case "portable timeout cleans state before preserving default TERM semantics"
    local case_dir="$TEST_TMP_DIR/timeout-interrupt-default"
    local target="$case_dir/target.sh" harness="$case_dir/harness.sh"
    local root_file="$case_dir/root.pid" harness_pid="" root_pid="" rc=0
    local leaks="" root_alive=false
    mkdir -p "$case_dir"

    cat > "$target" <<'EOF'
#!/bin/bash
printf '%s\n' "$$" > "$1"
exec /bin/sleep 30
EOF
    cat > "$harness" <<'EOF'
#!/bin/bash
set -u
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
log() { :; }
command() {
    if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
        return 1
    fi
    builtin command "$@"
}
ps() { return 1; }
run_with_timeout 30 "$TARGET" "$ROOT_FILE" >/dev/null 2>&1
EOF
    chmod +x "$target" "$harness"

    TMPDIR="$case_dir" PROJECT_ROOT="$PROJECT_ROOT" TARGET="$target" ROOT_FILE="$root_file" \
        /bin/bash "$harness" >/dev/null 2>&1 &
    harness_pid=$!
    if _wait_for_nonempty_file "$root_file"; then
        root_pid="$(< "$root_file")"
        kill -TERM "$harness_pid"
    else
        kill -KILL "$harness_pid" 2>/dev/null || true
    fi
    set +e
    wait "$harness_pid"
    rc=$?
    set -e
    sleep 0.2

    _pid_is_live "$root_pid" && root_alive=true
    leaks="$(find "$case_dir" -maxdepth 1 -name 'octo-timeout.*' -print)"
    if [[ "$root_alive" == true ]]; then kill -KILL "$root_pid" 2>/dev/null || true; fi

    if [[ "$rc" -eq 143 && -n "$root_pid" && "$root_alive" == false && -z "$leaks" ]]; then
        test_pass
    else
        test_fail "expected TERM rc=143, dead provider, and no marker; got rc=$rc root=${root_pid:-missing}/$root_alive leaks='${leaks:-none}'"
    fi
}

test_interruption_restores_returning_caller_trap() {
    test_case "portable timeout restores a returning caller TERM trap"
    local case_dir="$TEST_TMP_DIR/timeout-interrupt-trap"
    local target="$case_dir/target.sh" harness="$case_dir/harness.sh"
    local root_file="$case_dir/root.pid" trap_hits="$case_dir/trap-hits"
    local before="$case_dir/trap-before" after="$case_dir/trap-after"
    local harness_pid="" root_pid="" rc=0 hit_count=0 root_alive=false
    mkdir -p "$case_dir"

    cat > "$target" <<'EOF'
#!/bin/bash
printf '%s\n' "$$" > "$1"
exec /bin/sleep 30
EOF
    cat > "$harness" <<'EOF'
#!/bin/bash
set -u
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
log() { :; }
command() {
    if [[ "${1:-}" == "-v" && ( "${2:-}" == "gtimeout" || "${2:-}" == "timeout" ) ]]; then
        return 1
    fi
    builtin command "$@"
}
ps() { return 1; }
trap 'printf "TERM\n" >> "$TRAP_HITS"' TERM
trap -p TERM > "$TRAP_BEFORE"
set +e
run_with_timeout 30 "$TARGET" "$ROOT_FILE" >/dev/null 2>&1
rc=$?
set -e
trap -p TERM > "$TRAP_AFTER"
kill -TERM "$$"
exit "$rc"
EOF
    chmod +x "$target" "$harness"

    TMPDIR="$case_dir" PROJECT_ROOT="$PROJECT_ROOT" TARGET="$target" ROOT_FILE="$root_file" \
        TRAP_HITS="$trap_hits" TRAP_BEFORE="$before" TRAP_AFTER="$after" /bin/bash "$harness" &
    harness_pid=$!
    if _wait_for_nonempty_file "$root_file"; then
        root_pid="$(< "$root_file")"
        kill -TERM "$harness_pid"
    else
        kill -KILL "$harness_pid" 2>/dev/null || true
    fi
    set +e
    wait "$harness_pid"
    rc=$?
    set -e
    [[ -f "$trap_hits" ]] && hit_count="$(wc -l < "$trap_hits" | tr -d ' ')"
    sleep 0.2
    _pid_is_live "$root_pid" && root_alive=true
    if [[ "$root_alive" == true ]]; then kill -KILL "$root_pid" 2>/dev/null || true; fi

    if [[ "$rc" -eq 143 && "$hit_count" -eq 2 && -s "$before" &&
          -s "$after" ]] && cmp -s "$before" "$after" && [[ "$root_alive" == false ]]; then
        test_pass
    else
        test_fail "expected rc=143, restored trap invoked twice, and dead provider; got rc=$rc hits=$hit_count root=${root_pid:-missing}/$root_alive"
    fi
}

test_unbounded_interruption_while_waiting_for_status() {
    test_case "timeout-zero supervisor handles TERM while blocked on status FIFO"
    local case_dir="$TEST_TMP_DIR/unbounded-timeout-interrupt"
    local target="$case_dir/target.sh" harness="$case_dir/harness.sh"
    local root_file="$case_dir/root.pid" harness_pid="" root_pid="" rc=0
    local root_alive=false leaks=""
    mkdir -p "$case_dir"

    cat > "$target" <<'EOF'
#!/bin/bash
printf '%s\n' "$$" > "$1"
trap '' TERM
exec /bin/sleep 30
EOF
    cat > "$harness" <<'EOF'
#!/bin/bash
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
log() { :; }
OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP=true \
    run_with_timeout --portable-supervisor 0 "$TARGET" "$ROOT_FILE"
EOF
    chmod +x "$target" "$harness"

    TMPDIR="$case_dir" PROJECT_ROOT="$PROJECT_ROOT" TARGET="$target" ROOT_FILE="$root_file" \
        /bin/bash "$harness" >/dev/null 2>&1 &
    harness_pid=$!
    if _wait_for_nonempty_file "$root_file"; then
        root_pid="$(< "$root_file")"
        kill -TERM "$harness_pid"
    else
        kill -KILL "$harness_pid" 2>/dev/null || true
    fi
    set +e
    wait "$harness_pid"
    rc=$?
    set -e
    sleep 0.2

    _pid_is_live "$root_pid" && root_alive=true
    leaks="$(find "$case_dir" -maxdepth 1 -name 'octo-timeout-status.*' -print)"
    if [[ "$root_alive" == true ]]; then kill -KILL "$root_pid" 2>/dev/null || true; fi

    if [[ "$rc" -eq 143 && -n "$root_pid" && "$root_alive" == false && -z "$leaks" ]]; then
        test_pass
    else
        test_fail "expected TERM rc=143, dead provider, and no timeout state; got rc=$rc root=${root_pid:-missing}/$root_alive leaks='${leaks:-none}'"
    fi
}

test_elapsed_measurement_is_single_shell_portable() {
    test_case "elapsed bounds use Bash SECONDS rather than separate Python clocks"
    local source bad_clock
    source="$(< "$SCRIPT_DIR/test-heartbeat-timeout-fallback.sh")"
    bad_clock='python3 -c'
    if ! grep -q "$bad_clock.*time.monotonic" <<< "$source" && \
       [[ "$source" == *'SECONDS=0'* ]] && [[ "$source" == *'elapsed_seconds=$SECONDS'* ]]; then
        test_pass
    else
        test_fail "timeout elapsed checks must use one Bash 3.2-portable clock"
    fi
}

test_timeout_signals_root_without_ps
test_supervisor_isolates_provider_group_without_mutating_caller
test_timeout_timer_does_not_depend_on_path_sleep
test_completed_timer_failure_outranks_provider_success
test_simultaneous_successful_deadline_defers_to_provider_completion
test_malformed_timeout_fails_before_provider_launch
test_timeout_overflow_fails_before_provider_launch
test_timeout_decimal_normalization_is_bounded
test_timer_failure_fails_closed_and_reaps_provider
test_timer_runtime_failure_fails_closed
test_timeout_kills_term_resistant_descendant_without_ps
test_interruption_cleans_timeout_state_and_preserves_default_term
test_interruption_restores_returning_caller_trap
test_unbounded_interruption_while_waiting_for_status
test_elapsed_measurement_is_single_shell_portable

test_summary
