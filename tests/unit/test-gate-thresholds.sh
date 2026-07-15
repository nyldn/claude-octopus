#!/bin/bash
# tests/unit/test-gate-thresholds.sh
# Tests configurable quality gate thresholds (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Configurable Quality Gate Thresholds"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

test_gate_function_exists() {
    test_case "get_gate_threshold function exists"

    if grep -q "get_gate_threshold()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "get_gate_threshold function not found"
    fi
}

test_gate_env_vars_defined() {
    test_case "Gate threshold env vars are defined"

    local found=true
    for var in OCTOPUS_GATE_PROBE OCTOPUS_GATE_GRASP OCTOPUS_GATE_TANGLE OCTOPUS_GATE_INK OCTOPUS_GATE_SECURITY; do
        if ! grep -q "$var" "$ALL_SRC"; then
            test_fail "Missing env var: $var"
            found=false
            break
        fi
    done

    if [[ "$found" == "true" ]]; then
        test_pass
    fi
}

test_gate_probe_default() {
    test_case "Probe phase default threshold is 50"

    if grep -q 'OCTOPUS_GATE_PROBE.*50' "$ALL_SRC"; then
        test_pass
    else
        test_fail "Probe default not 50"
    fi
}

test_gate_security_floor() {
    test_case "Security gate has floor enforcement"

    if grep -q 'Security floor\|security.*clamp\|threshold.*-lt 100' "$ALL_SRC"; then
        test_pass
    else
        test_fail "Security floor enforcement not found"
    fi
}

test_gate_alias_support() {
    test_case "Phase aliases (discover/define/develop/deliver) are supported"

    # Check directly in the get_gate_threshold function
    if grep -A 30 "get_gate_threshold()" "$ALL_SRC" | grep "discover\|define\|develop\|deliver" >/dev/null; then
        test_pass
    else
        test_fail "Phase aliases not found in get_gate_threshold"
    fi
}

test_gate_fallback() {
    test_case "Unknown phases fall back to QUALITY_THRESHOLD"

    if grep -A 65 "get_gate_threshold()" "$ALL_SRC" | grep "QUALITY_THRESHOLD" >/dev/null; then
        test_pass
    else
        test_fail "Fallback to QUALITY_THRESHOLD not found"
    fi
}

test_tangle_uses_gate_threshold() {
    test_case "validate_tangle_results uses get_gate_threshold"

    if grep -A 80 "validate_tangle_results()" "$ALL_SRC" | grep "get_gate_threshold" >/dev/null; then
        test_pass
    else
        test_fail "validate_tangle_results doesn't use get_gate_threshold"
    fi
}

test_dry_run_with_thresholds() {
    test_case "Dry-run works with threshold env vars"

    local output
    output=$(OCTOPUS_GATE_TANGLE=60 "$PROJECT_ROOT/scripts/orchestrate.sh" -n tangle "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run failed: $exit_code"
    fi
}

test_gate_env_override() {
    test_case "Gate threshold env var override works"

    # Verify the env var pattern allows override
    if grep -q 'OCTOPUS_GATE_PROBE.*:-50' "$ALL_SRC" || \
       grep -q 'OCTOPUS_GATE_PROBE:-50' "$ALL_SRC"; then
        test_pass
    else
        test_fail "Env var override pattern not found"
    fi
}

# Run tests
test_gate_function_exists
test_gate_env_vars_defined
test_gate_probe_default
test_gate_security_floor
test_gate_alias_support
test_gate_fallback
test_tangle_uses_gate_threshold
test_dry_run_with_thresholds
test_gate_env_override

rm -f "$ALL_SRC"
test_summary
