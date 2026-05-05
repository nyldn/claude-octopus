#!/bin/bash
# tests/unit/test-crash-recovery.sh
# Tests crash-recovery with secret sanitization (v8.19.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Crash-Recovery with Secret Sanitization"

# Combined search target (functions decomposed to lib/ in v9.7.7+)
ALL_SRC=$(mktemp)
trap 'rm -f "$ALL_SRC"' EXIT
cat "$PROJECT_ROOT/scripts/orchestrate.sh" "$PROJECT_ROOT/scripts/lib/"*.sh > "$ALL_SRC" 2>/dev/null

test_sanitize_secrets_function_exists() {
    test_case "sanitize_secrets function exists"

    if grep -q "sanitize_secrets()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "sanitize_secrets function not found"
    fi
}

test_checkpoint_functions_exist() {
    test_case "Checkpoint functions exist"

    if grep -q "save_agent_checkpoint()" "$ALL_SRC" && \
       grep -q "load_agent_checkpoint()" "$ALL_SRC" && \
       grep -q "cleanup_expired_checkpoints()" "$ALL_SRC"; then
        test_pass
    else
        test_fail "Not all checkpoint functions found"
    fi
}

test_sanitize_api_keys() {
    test_case "Sanitizes sk-* API keys"

    local func_body
    func_body=$(sed -n '/^sanitize_secrets()/,/^}/p' "$ALL_SRC")

    if grep -q 'sk-.*REDACTED' <<< "$func_body"; then
        test_pass
    else
        test_fail "sk-* API key sanitization not found"
    fi
}

test_sanitize_aws_keys() {
    test_case "Sanitizes AKIA* AWS keys"

    local func_body
    func_body=$(sed -n '/^sanitize_secrets()/,/^}/p' "$ALL_SRC")

    if grep -q 'AKIA.*REDACTED' <<< "$func_body"; then
        test_pass
    else
        test_fail "AKIA* AWS key sanitization not found"
    fi
}

test_sanitize_github_tokens() {
    test_case "Sanitizes ghp_/gho_* GitHub tokens"

    local func_body
    func_body=$(sed -n '/^sanitize_secrets()/,/^}/p' "$ALL_SRC")

    if grep -q 'ghp_.*REDACTED' <<< "$func_body" && grep -q 'gho_.*REDACTED' <<< "$func_body"; then
        test_pass
    else
        test_fail "GitHub token sanitization not found"
    fi
}

test_sanitize_bearer_tokens() {
    test_case "Sanitizes Bearer tokens"

    local func_body
    func_body=$(sed -n '/^sanitize_secrets()/,/^}/p' "$ALL_SRC")

    if grep -q 'Bearer.*REDACTED' <<< "$func_body"; then
        test_pass
    else
        test_fail "Bearer token sanitization not found"
    fi
}

test_sanitize_jwt_tokens() {
    test_case "Sanitizes JWT tokens"

    local func_body
    func_body=$(sed -n '/^sanitize_secrets()/,/^}/p' "$ALL_SRC")

    if grep -q 'eyJ.*REDACTED' <<< "$func_body"; then
        test_pass
    else
        test_fail "JWT token sanitization not found"
    fi
}

test_sanitize_private_keys() {
    test_case "Sanitizes private key blocks"

    local func_body
    func_body=$(sed -n '/^sanitize_secrets()/,/^}/p' "$ALL_SRC")

    if grep -q 'PRIVATE KEY.*REDACTED\|BEGIN.*REDACTED' <<< "$func_body"; then
        test_pass
    else
        test_fail "Private key sanitization not found"
    fi
}

test_sanitize_connection_strings() {
    test_case "Sanitizes database connection strings"

    local func_body
    func_body=$(sed -n '/^sanitize_secrets()/,/^}/p' "$ALL_SRC")

    if grep -q 'postgres://.*REDACTED' <<< "$func_body" && \
       grep -q 'mysql://.*REDACTED' <<< "$func_body" && \
       grep -q 'mongodb://.*REDACTED' <<< "$func_body" && \
       grep -q 'redis://.*REDACTED' <<< "$func_body"; then
        test_pass
    else
        test_fail "Connection string sanitization not found"
    fi
}

test_sanitize_password_patterns() {
    test_case "Sanitizes password= patterns"

    local func_body
    func_body=$(sed -n '/^sanitize_secrets()/,/^}/p' "$ALL_SRC")

    if grep -q 'password=.*REDACTED' <<< "$func_body"; then
        test_pass
    else
        test_fail "Password pattern sanitization not found"
    fi
}

test_sanitize_gitlab_slack() {
    test_case "Sanitizes GitLab PATs and Slack tokens"

    local func_body
    func_body=$(sed -n '/^sanitize_secrets()/,/^}/p' "$ALL_SRC")

    if grep -q 'glpat-.*REDACTED' <<< "$func_body" && \
       grep -q 'xox.*REDACTED' <<< "$func_body"; then
        test_pass
    else
        test_fail "GitLab/Slack sanitization not found"
    fi
}

test_checkpoint_debounce() {
    test_case "Checkpoint has 5-minute debounce"

    local func_body
    func_body=$(sed -n '/^save_agent_checkpoint()/,/^}/p' "$ALL_SRC")

    if grep -q "300\|5 min" <<< "$func_body"; then
        test_pass
    else
        test_fail "5-minute debounce not found"
    fi
}

test_checkpoint_expiry() {
    test_case "Checkpoints expire after 24h"

    local func_body
    func_body=$(sed -n '/^load_agent_checkpoint()/,/^}/p' "$ALL_SRC")

    if grep -q "86400" <<< "$func_body"; then
        test_pass
    else
        test_fail "24h expiry (86400) not found"
    fi
}

test_checkpoint_truncation() {
    test_case "Checkpoint output truncated to 4096 chars"

    local func_body
    func_body=$(sed -n '/^save_agent_checkpoint()/,/^}/p' "$ALL_SRC")

    if grep -q "4096" <<< "$func_body"; then
        test_pass
    else
        test_fail "4096 char truncation not found"
    fi
}

test_checkpoint_in_spawn_agent_failure() {
    test_case "Checkpoint saved in spawn_agent failure path"

    if grep -B 5 -A 5 "save_agent_checkpoint" "$ALL_SRC" | grep -q "FAILED\|failed\|spawn_agent"; then
        test_pass
    else
        test_fail "Checkpoint not saved on failure"
    fi
}

test_checkpoint_in_spawn_agent_start() {
    test_case "Checkpoint loaded in spawn_agent start"

    if grep -A 70 "spawn_agent()" "$ALL_SRC" | grep -q "load_agent_checkpoint"; then
        test_pass
    else
        test_fail "Checkpoint not loaded at spawn_agent start"
    fi
}

test_cleanup_in_embrace() {
    test_case "cleanup_expired_checkpoints called in embrace_full_workflow"

    if grep -A 30 "embrace_full_workflow()" "$ALL_SRC" | grep -q "cleanup_expired_checkpoints"; then
        test_pass
    else
        test_fail "Cleanup not called in embrace_full_workflow"
    fi
}

test_dry_run_with_crash_recovery() {
    test_case "Dry-run works with crash-recovery code"

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
test_sanitize_secrets_function_exists
test_checkpoint_functions_exist
test_sanitize_api_keys
test_sanitize_aws_keys
test_sanitize_github_tokens
test_sanitize_bearer_tokens
test_sanitize_jwt_tokens
test_sanitize_private_keys
test_sanitize_connection_strings
test_sanitize_password_patterns
test_sanitize_gitlab_slack
test_checkpoint_debounce
test_checkpoint_expiry
test_checkpoint_truncation
test_checkpoint_in_spawn_agent_failure
test_checkpoint_in_spawn_agent_start
test_cleanup_in_embrace
test_dry_run_with_crash_recovery

test_summary
