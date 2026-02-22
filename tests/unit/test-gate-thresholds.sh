#!/bin/bash
# tests/unit/test-gate-thresholds.sh
# Tests configurable quality gate thresholds (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Configurable Quality Gate Thresholds"

# Source orchestrate.sh functions (dry-run mode)
setup_orchestrate() {
    export DRY_RUN=true
    export WORKSPACE_DIR="$TEST_TMP_DIR"
    export QUALITY_THRESHOLD=75
    export OCTOPUS_GATE_PROBE=50
    export OCTOPUS_GATE_GRASP=75
    export OCTOPUS_GATE_TANGLE=75
    export OCTOPUS_GATE_INK=80
    export OCTOPUS_GATE_SECURITY=100
    # Source just the function definitions
    source <(sed -n '/^get_gate_threshold()/,/^}/p' "$PROJECT_ROOT/scripts/orchestrate.sh" 2>/dev/null) || true
}

test_gate_function_exists() {
    test_case "get_gate_threshold function exists in orchestrate.sh"

    if grep -q "get_gate_threshold()" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "get_gate_threshold function not found"
    fi
}

test_gate_env_vars_defined() {
    test_case "Gate threshold env vars are defined"

    local found=true
    for var in OCTOPUS_GATE_PROBE OCTOPUS_GATE_GRASP OCTOPUS_GATE_TANGLE OCTOPUS_GATE_INK OCTOPUS_GATE_SECURITY; do
        if ! grep -q "$var" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
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

    if grep -q 'OCTOPUS_GATE_PROBE.*50' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "Probe default not 50"
    fi
}

test_gate_security_floor() {
    test_case "Security gate has floor enforcement"

    if grep -q 'Security floor\|security.*clamp\|threshold.*-lt 100' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "Security floor enforcement not found"
    fi
}

test_gate_alias_support() {
    test_case "Phase aliases (discover/define/develop/deliver) are supported"

    local aliases_found=0
    for alias in discover define develop deliver; do
        if grep -q "$alias)" "$PROJECT_ROOT/scripts/orchestrate.sh" | head -1; then
            ((aliases_found++)) || true
        fi
    done

    # Check directly in the get_gate_threshold function
    if grep -A 30 "get_gate_threshold()" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "discover\|define\|develop\|deliver"; then
        test_pass
    else
        test_fail "Phase aliases not found in get_gate_threshold"
    fi
}

test_gate_fallback() {
    test_case "Unknown phases fall back to QUALITY_THRESHOLD"

    if grep -A 30 "get_gate_threshold()" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "QUALITY_THRESHOLD"; then
        test_pass
    else
        test_fail "Fallback to QUALITY_THRESHOLD not found"
    fi
}

test_tangle_uses_gate_threshold() {
    test_case "validate_tangle_results uses get_gate_threshold"

    if grep -A 80 "validate_tangle_results()" "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q "get_gate_threshold"; then
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
    if grep -q 'OCTOPUS_GATE_PROBE.*:-50' "$PROJECT_ROOT/scripts/orchestrate.sh" || \
       grep -q 'OCTOPUS_GATE_PROBE:-50' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
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

test_summary
