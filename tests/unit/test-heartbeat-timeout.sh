#!/bin/bash
# tests/unit/test-heartbeat-timeout.sh
# Tests agent heartbeat & dynamic timeout (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Agent Heartbeat & Dynamic Timeout"

test_heartbeat_functions_exist() {
    test_case "Heartbeat functions exist in orchestrate.sh"

    if grep -q "start_heartbeat_monitor()" "$PROJECT_ROOT/scripts/orchestrate.sh" && \
       grep -q "check_agent_heartbeat()" "$PROJECT_ROOT/scripts/orchestrate.sh" && \
       grep -q "cleanup_heartbeat()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "Not all heartbeat functions found"
    fi
}

test_dynamic_timeout_function_exists() {
    test_case "compute_dynamic_timeout function exists"

    if grep -q "compute_dynamic_timeout()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "compute_dynamic_timeout function not found"
    fi
}

test_timeout_env_var_defined() {
    test_case "OCTOPUS_AGENT_TIMEOUT env var defined"

    if grep -q "OCTOPUS_AGENT_TIMEOUT" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "OCTOPUS_AGENT_TIMEOUT not defined"
    fi
}

test_timeout_direct_mode() {
    test_case "Direct/lightweight tasks get 60s timeout"

    local func_body
    func_body=$(sed -n '/^compute_dynamic_timeout()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q 'direct\|lightweight' && echo "$func_body" | grep -q '"60"'; then
        test_pass
    else
        test_fail "Direct mode timeout not 60s"
    fi
}

test_timeout_full_mode() {
    test_case "Full/premium tasks get 300s timeout"

    local func_body
    func_body=$(sed -n '/^compute_dynamic_timeout()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q 'full\|premium' && echo "$func_body" | grep -q '"300"'; then
        test_pass
    else
        test_fail "Full mode timeout not 300s"
    fi
}

test_timeout_crossfire_mode() {
    test_case "Crossfire/debate tasks get 180s timeout"

    local func_body
    func_body=$(sed -n '/^compute_dynamic_timeout()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q 'crossfire\|debate' && echo "$func_body" | grep -q '"180"'; then
        test_pass
    else
        test_fail "Crossfire mode timeout not 180s"
    fi
}

test_timeout_security_mode() {
    test_case "Security tasks get 240s timeout"

    local func_body
    func_body=$(sed -n '/^compute_dynamic_timeout()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q 'security\|audit' && echo "$func_body" | grep -q '"240"'; then
        test_pass
    else
        test_fail "Security mode timeout not 240s"
    fi
}

test_timeout_env_override() {
    test_case "OCTOPUS_AGENT_TIMEOUT env var overrides computed timeout"

    local func_body
    func_body=$(sed -n '/^compute_dynamic_timeout()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "OCTOPUS_AGENT_TIMEOUT"; then
        test_pass
    else
        test_fail "Env override not in compute_dynamic_timeout"
    fi
}

test_heartbeat_in_spawn_agent() {
    test_case "Heartbeat monitor started in spawn_agent"

    if grep -A 5 'local pid=\$!' "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "start_heartbeat_monitor"; then
        test_pass
    else
        test_fail "start_heartbeat_monitor not called after PID assignment"
    fi
}

test_heartbeat_macos_linux_compat() {
    test_case "Heartbeat check has macOS/Linux stat compatibility"

    local func_body
    func_body=$(sed -n '/^check_agent_heartbeat()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh")

    if echo "$func_body" | grep -q "stat -f" && echo "$func_body" | grep -q "stat -c"; then
        test_pass
    else
        test_fail "macOS/Linux stat compatibility not found"
    fi
}

test_dynamic_timeout_in_run_agent_sync() {
    test_case "run_agent_sync uses compute_dynamic_timeout"

    if grep -A 20 "run_agent_sync()" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "compute_dynamic_timeout"; then
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

test_summary
