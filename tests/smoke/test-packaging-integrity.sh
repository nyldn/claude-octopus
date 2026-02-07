#!/bin/bash
# tests/smoke/test-packaging-integrity.sh
# Validates all sourced scripts and required files exist in the package
# Regression test for issue #19 (missing metrics-tracker.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Packaging Integrity (Regression: Issue #19)"

ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"

test_sourced_scripts_exist() {
    test_case "All scripts sourced by orchestrate.sh exist"

    if [[ ! -f "$ORCHESTRATE" ]]; then
        test_fail "orchestrate.sh not found"
        return 1
    fi

    local missing=0
    local script_dir
    script_dir=$(dirname "$ORCHESTRATE")

    # Extract all source statements from orchestrate.sh
    # Matches: source "${SCRIPT_DIR}/foo.sh" and source "$SCRIPT_DIR/foo.sh"
    while IFS= read -r line; do
        # Extract the filename from source "${SCRIPT_DIR}/filename.sh"
        local sourced_file
        sourced_file=$(echo "$line" | grep -oE 'source "\$\{?SCRIPT_DIR\}?/[^"]+' | sed 's|source "\${SCRIPT_DIR}/||;s|source "$SCRIPT_DIR/||')

        if [[ -n "$sourced_file" ]]; then
            local full_path="${script_dir}/${sourced_file}"
            if [[ ! -f "$full_path" ]]; then
                echo "  MISSING: ${sourced_file} (referenced in orchestrate.sh)"
                missing=$((missing + 1))
            fi
        fi
    done < <(grep '^source ' "$ORCHESTRATE" 2>/dev/null)

    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "$missing sourced script(s) missing from package"
        return 1
    fi
}

test_metrics_tracker_exists() {
    test_case "metrics-tracker.sh exists (regression: issue #19)"

    local expected="$PROJECT_ROOT/scripts/metrics-tracker.sh"

    if [[ -f "$expected" ]]; then
        test_pass
    else
        test_fail "metrics-tracker.sh missing - this was bug #19"
        return 1
    fi
}

test_state_manager_exists() {
    test_case "state-manager.sh exists"

    local expected="$PROJECT_ROOT/scripts/state-manager.sh"

    if [[ -f "$expected" ]]; then
        test_pass
    else
        test_fail "state-manager.sh missing from scripts/"
        return 1
    fi
}

test_hook_scripts_exist() {
    test_case "All hook scripts referenced in hooks/ are valid"

    local hooks_dir="$PROJECT_ROOT/hooks"

    if [[ ! -d "$hooks_dir" ]]; then
        test_skip "hooks/ directory not found"
        return 0
    fi

    local missing=0
    for hook in "$hooks_dir"/*.sh; do
        [[ ! -f "$hook" ]] && continue

        # Verify hook is valid bash
        if ! bash -n "$hook" 2>/dev/null; then
            echo "  INVALID SYNTAX: $(basename "$hook")"
            missing=$((missing + 1))
        fi

        # Verify hook is executable
        if [[ ! -x "$hook" ]]; then
            echo "  NOT EXECUTABLE: $(basename "$hook")"
            missing=$((missing + 1))
        fi
    done

    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "$missing hook script issue(s) found"
        return 1
    fi
}

test_orchestrate_can_source_deps() {
    test_case "orchestrate.sh can source all dependencies without error"

    if [[ ! -f "$ORCHESTRATE" ]]; then
        test_fail "orchestrate.sh not found"
        return 1
    fi

    # Extract just the source lines and try to execute them in a subshell
    # This validates that all source targets resolve correctly
    local result
    result=$(SCRIPT_DIR="$(dirname "$ORCHESTRATE")" bash -c '
        set -euo pipefail
        SCRIPT_DIR="'"$(dirname "$ORCHESTRATE")"'"
        # Source each dependency
        while IFS= read -r line; do
            eval "$line" 2>/dev/null || echo "FAIL: $line"
        done < <(grep "^source " "'"$ORCHESTRATE"'" 2>/dev/null)
        echo "OK"
    ' 2>&1 | tail -1)

    if [[ "$result" == "OK" ]]; then
        test_pass
    else
        test_fail "Failed to source dependencies: $result"
        return 1
    fi
}

# Run tests
test_sourced_scripts_exist
test_metrics_tracker_exists
test_state_manager_exists
test_hook_scripts_exist
test_orchestrate_can_source_deps

test_summary
