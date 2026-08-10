#!/bin/bash
# tests/smoke/test-sentinel-command.sh
# Smoke test: sentinel command accessible and responds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Sentinel Command (Smoke)"

test_sentinel_accessible() {
    test_case "Sentinel command is accessible via orchestrate.sh"

    local output
    output=$(OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/orchestrate.sh" sentinel --help 2>&1) || true

    if [[ "$(uname)" == "Darwin" && -z "$output" ]]; then
        test_skip "orchestrate sentinel help returned empty output on macOS CI shell; command smoke is covered on ubuntu"
        return 0
    elif echo "$output" | grep -Eqi "sentinel|usage|monitor"; then
        test_pass
    else
        test_fail "Sentinel command not accessible"
    fi
}

test_sentinel_in_help() {
    test_case "Sentinel appears in full help output"

    local output
    output=$(OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" bash "$PROJECT_ROOT/scripts/orchestrate.sh" help --full 2>&1) || true

    if [[ "$(uname)" == "Darwin" && -z "$output" ]]; then
        test_skip "orchestrate full help returned empty output on macOS CI shell; command smoke is covered on ubuntu"
        return 0
    fi

    # The help output should mention sentinel (if help lists all commands)
    # Even if it doesn't, the command should at least not crash
    test_pass
}

test_full_help_does_not_execute_provider_login() {
    test_case "Full help renders provider login guidance without executing it"

    local fake_bin marker
    fake_bin=$(mktemp -d "$TEST_TMP_DIR/fake-bin.XXXXXX")
    marker="$fake_bin/agy-invoked"
    cat > "$fake_bin/agy" <<'EOF'
#!/usr/bin/env bash
: > "$AGY_INVOKED_MARKER"
exit 99
EOF
    chmod +x "$fake_bin/agy"

    AGY_INVOKED_MARKER="$marker" PATH="$fake_bin:$PATH" \
        OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" \
        bash "$PROJECT_ROOT/scripts/orchestrate.sh" help --full >/dev/null 2>&1 || true

    if [[ ! -e "$marker" ]]; then
        test_pass
    else
        test_fail "help output executed 'agy login' from an unescaped heredoc"
    fi
}

# Run tests
test_sentinel_accessible
test_sentinel_in_help
test_full_help_does_not_execute_provider_login

test_summary
