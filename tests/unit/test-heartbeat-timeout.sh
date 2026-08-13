#!/bin/bash
# tests/unit/test-heartbeat-timeout.sh
# Tests agent heartbeat & dynamic timeout (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Agent Heartbeat & Dynamic Timeout"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

test_heartbeat_functions_exist() {
    test_case "Heartbeat functions exist"

    if grep -q "start_heartbeat_monitor()" "$ALL_SRC" && \
       grep -q "check_agent_heartbeat()" "$ALL_SRC" && \
       grep -q "cleanup_heartbeat()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "Not all heartbeat functions found"
    fi
}

test_dynamic_timeout_function_exists() {
    test_case "compute_dynamic_timeout function exists"

    if grep -q "compute_dynamic_timeout()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "compute_dynamic_timeout function not found"
    fi
}

test_timeout_env_var_defined() {
    test_case "OCTOPUS_AGENT_TIMEOUT env var defined"

    if grep -q "OCTOPUS_AGENT_TIMEOUT" "$ALL_SRC"; then
        test_pass
    else
        test_fail "OCTOPUS_AGENT_TIMEOUT not defined"
    fi
}

test_timeout_direct_mode() {
    test_case "Direct/lightweight tasks get 60s timeout"

    local func_body
    func_body=$(sed -n '/^compute_dynamic_timeout()/,/^}/p' "$ALL_SRC")

    if echo "$func_body" | grep -q 'direct\|lightweight' && echo "$func_body" | grep -q '"60"'; then
        test_pass
    else
        test_fail "Direct mode timeout not 60s"
    fi
}

test_timeout_full_mode() {
    test_case "Full/premium tasks get 300s timeout"

    local func_body
    func_body=$(sed -n '/^compute_dynamic_timeout()/,/^}/p' "$ALL_SRC")

    if echo "$func_body" | grep -q 'full\|premium' && echo "$func_body" | grep -q '300'; then
        test_pass
    else
        test_fail "Full mode timeout not based on 300s"
    fi
}

test_timeout_crossfire_mode() {
    test_case "Crossfire/debate tasks get 180s timeout"

    local func_body
    func_body=$(sed -n '/^compute_dynamic_timeout()/,/^}/p' "$ALL_SRC")

    if echo "$func_body" | grep -q 'crossfire\|debate' && echo "$func_body" | grep -q '180'; then
        test_pass
    else
        test_fail "Crossfire mode timeout not based on 180s"
    fi
}

test_timeout_security_mode() {
    test_case "Security tasks get 240s timeout"

    local func_body
    func_body=$(sed -n '/^compute_dynamic_timeout()/,/^}/p' "$ALL_SRC")

    if echo "$func_body" | grep -q 'security\|audit' && echo "$func_body" | grep -q '240'; then
        test_pass
    else
        test_fail "Security mode timeout not based on 240s"
    fi
}

test_timeout_env_override() {
    test_case "OCTOPUS_AGENT_TIMEOUT env var overrides computed timeout"

    local func_body
    func_body=$(sed -n '/^compute_dynamic_timeout()/,/^}/p' "$ALL_SRC")

    if echo "$func_body" | grep -q "OCTOPUS_AGENT_TIMEOUT"; then
        test_pass
    else
        test_fail "Env override not in compute_dynamic_timeout"
    fi
}

test_heartbeat_in_spawn_agent() {
    test_case "Heartbeat monitor started in spawn_agent"

    local spawn_body pid_line heartbeat_line
    spawn_body=$(sed -n '/^spawn_agent()/,/^spawn_agent_capture_pid()/p' \
        "$PROJECT_ROOT/scripts/lib/spawn.sh")
    pid_line=$(printf '%s\n' "$spawn_body" | awk '/local pid=\$!/{print NR; exit}')
    heartbeat_line=$(printf '%s\n' "$spawn_body" | \
        awk '/start_heartbeat_monitor "\$pid" "\$task_id"/{print NR; exit}')

    if [[ -n "$pid_line" && -n "$heartbeat_line" && "$heartbeat_line" -gt "$pid_line" ]]; then
        test_pass
    else
        test_fail "start_heartbeat_monitor not called after PID assignment"
    fi
}

test_heartbeat_macos_linux_compat() {
    test_case "Heartbeat check has macOS/Linux stat compatibility"

    local func_body
    func_body=$(sed -n '/^check_agent_heartbeat()/,/^}/p' "$ALL_SRC")

    if echo "$func_body" | grep -q "stat -f" && echo "$func_body" | grep -q "stat -c"; then
        test_pass
    else
        test_fail "macOS/Linux stat compatibility not found"
    fi
}

test_dynamic_timeout_in_run_agent_sync() {
    test_case "run_agent_sync uses compute_dynamic_timeout"

    if grep -A 20 "run_agent_sync()" "$ALL_SRC" | grep -q "compute_dynamic_timeout"; then
        test_pass
    else
        test_fail "compute_dynamic_timeout not used in run_agent_sync"
    fi
}

test_dry_run_with_heartbeat() {
    test_case "Dry-run works with heartbeat code"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n tangle "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run failed: $exit_code"
    fi
}

# Run tests
test_heartbeat_functions_exist
test_dynamic_timeout_function_exists
test_timeout_env_var_defined
test_timeout_direct_mode
test_timeout_full_mode
test_timeout_crossfire_mode
test_timeout_security_mode
test_timeout_env_override
test_heartbeat_in_spawn_agent
test_heartbeat_macos_linux_compat
test_dynamic_timeout_in_run_agent_sync
test_dry_run_with_heartbeat

rm -f "$ALL_SRC"
test_summary
