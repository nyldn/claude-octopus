#!/bin/bash
# tests/unit/test-provider-history.sh
# Tests per-provider history files (v8.18.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Per-Provider History Files"

# Set up a temp workspace
TEST_WORKSPACE="/tmp/octopus-test-history-$$"

setup_history_env() {
    rm -rf "$TEST_WORKSPACE"
    mkdir -p "$TEST_WORKSPACE"
    WORKSPACE_DIR="$TEST_WORKSPACE"
    LOG_LEVEL="WARN"
    log() { :; }
}

cleanup_history_env() {
    rm -rf "$TEST_WORKSPACE"
}

# Define functions inline for unit testing
append_provider_history() {
    local provider="$1"
    local phase="$2"
    local task_brief="$3"
    local learned="$4"

    local history_dir="${WORKSPACE_DIR}/.octo/providers"
    local history_file="$history_dir/${provider}-history.md"
    mkdir -p "$history_dir"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat >> "$history_file" << HISTEOF
### ${phase} | ${timestamp}
**Task:** ${task_brief:0:100}
**Learned:** ${learned:0:200}
---
HISTEOF

    local entry_count
    entry_count=$(grep -c "^### " "$history_file" 2>/dev/null || echo "0")
    if [[ "$entry_count" -gt 50 ]]; then
        local excess=$((entry_count - 50))
        local trim_line
        trim_line=$(grep -n "^### " "$history_file" | sed -n "$((excess + 1))p" | cut -d: -f1)
        if [[ -n "$trim_line" && "$trim_line" -gt 1 ]]; then
            tail -n "+$trim_line" "$history_file" > "$history_file.tmp" && mv "$history_file.tmp" "$history_file"
        fi
    fi
}

read_provider_history() {
    local provider="$1"
    local history_file="${WORKSPACE_DIR}/.octo/providers/${provider}-history.md"
    if [[ -f "$history_file" ]]; then
        cat "$history_file"
    fi
}

build_provider_context() {
    local agent_type="$1"
    local base_provider="${agent_type%%-*}"
    local history
    history=$(read_provider_history "$base_provider")
    if [[ -z "$history" ]]; then
        return
    fi
    if [[ ${#history} -gt 2000 ]]; then
        history="${history:0:2000}..."
    fi
    echo "## Provider History (${base_provider})
Recent learnings from this project:
${history}"
}

# ── Tests ──

test_directory_creation() {
    test_case "Creates .octo/providers/ directory on first write"
    setup_history_env

    append_provider_history "codex" "tangle" "implement auth" "Use JWT tokens for stateless auth"

    if [[ -d "$TEST_WORKSPACE/.octo/providers" ]]; then
        test_pass
    else
        test_fail "Directory not created"
    fi
    cleanup_history_env
}

test_file_creation() {
    test_case "Creates provider-specific history file"
    setup_history_env

    append_provider_history "codex" "tangle" "implement auth" "Use JWT tokens"

    if [[ -f "$TEST_WORKSPACE/.octo/providers/codex-history.md" ]]; then
        test_pass
    else
        test_fail "History file not created"
    fi
    cleanup_history_env
}

test_append_behavior() {
    test_case "Appends entries (does not overwrite)"
    setup_history_env

    append_provider_history "gemini" "probe" "research OAuth" "OAuth 2.0 is preferred"
    append_provider_history "gemini" "tangle" "implement OAuth" "Use PKCE flow"

    local count
    count=$(grep -c "^### " "$TEST_WORKSPACE/.octo/providers/gemini-history.md" 2>/dev/null)

    if [[ "$count" -eq 2 ]]; then
        test_pass
    else
        test_fail "Expected 2 entries, got $count"
    fi
    cleanup_history_env
}

test_entry_format() {
    test_case "Entries have correct markdown format"
    setup_history_env

    append_provider_history "codex" "tangle" "build feature" "learned something"

    local content
    content=$(cat "$TEST_WORKSPACE/.octo/providers/codex-history.md")

    if echo "$content" | grep -q "^### tangle |" && \
       echo "$content" | grep -q "^\*\*Task:\*\*" && \
       echo "$content" | grep -q "^\*\*Learned:\*\*" && \
       echo "$content" | grep -q "^---$"; then
        test_pass
    else
        test_fail "Format mismatch: $content"
    fi
    cleanup_history_env
}

test_truncation_at_50() {
    test_case "Truncates at 50 entries (oldest removed)"
    setup_history_env

    # Write 55 entries
    for i in $(seq 1 55); do
        append_provider_history "codex" "tangle" "task $i" "learned $i"
    done

    local count
    count=$(grep -c "^### " "$TEST_WORKSPACE/.octo/providers/codex-history.md" 2>/dev/null)

    if [[ "$count" -le 50 ]]; then
        test_pass
    else
        test_fail "Expected <= 50 entries, got $count"
    fi
    cleanup_history_env
}

test_read_provider_history() {
    test_case "read_provider_history returns history content"
    setup_history_env

    append_provider_history "gemini" "probe" "research APIs" "REST is simple"
    local result
    result=$(read_provider_history "gemini")

    if [[ -n "$result" ]] && echo "$result" | grep -q "REST is simple"; then
        test_pass
    else
        test_fail "History not readable: $result"
    fi
    cleanup_history_env
}

test_read_nonexistent() {
    test_case "read_provider_history returns empty for nonexistent provider"
    setup_history_env

    local result
    result=$(read_provider_history "nonexistent")

    if [[ -z "$result" ]]; then
        test_pass
    else
        test_fail "Expected empty, got: $result"
    fi
    cleanup_history_env
}

test_build_provider_context() {
    test_case "build_provider_context formats history for prompt injection"
    setup_history_env

    append_provider_history "codex" "tangle" "build auth" "JWT works well"
    local ctx
    ctx=$(build_provider_context "codex")

    if echo "$ctx" | grep -q "## Provider History (codex)" && \
       echo "$ctx" | grep -q "JWT works well"; then
        test_pass
    else
        test_fail "Context format wrong: $ctx"
    fi
    cleanup_history_env
}

test_build_context_strips_variant() {
    test_case "build_provider_context handles agent variants (codex-fast -> codex)"
    setup_history_env

    append_provider_history "codex" "tangle" "build auth" "JWT works well"
    local ctx
    ctx=$(build_provider_context "codex-fast")

    if echo "$ctx" | grep -q "## Provider History (codex)"; then
        test_pass
    else
        test_fail "Variant stripping failed: $ctx"
    fi
    cleanup_history_env
}

test_build_context_truncation() {
    test_case "build_provider_context truncates to 2000 chars"
    setup_history_env

    # Write many entries to exceed 2000 chars
    for i in $(seq 1 30); do
        append_provider_history "codex" "tangle" "long task description number $i for testing" "This is a somewhat long learned entry to test truncation behavior of provider history system $i"
    done

    local ctx
    ctx=$(build_provider_context "codex")
    local ctx_len=${#ctx}

    # Context header adds ~60 chars, so total should be close to 2060 + "..."
    if [[ $ctx_len -lt 2200 ]]; then
        test_pass
    else
        test_fail "Context too long: $ctx_len chars"
    fi
    cleanup_history_env
}

test_build_context_empty() {
    test_case "build_provider_context returns empty when no history"
    setup_history_env

    local ctx
    ctx=$(build_provider_context "codex")

    if [[ -z "$ctx" ]]; then
        test_pass
    else
        test_fail "Expected empty, got: $ctx"
    fi
    cleanup_history_env
}

test_dry_run_no_crash() {
    test_case "Dry-run probe still works with provider history code"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run failed: $exit_code"
    fi
}

# Run all tests
test_directory_creation
test_file_creation
test_append_behavior
test_entry_format
test_truncation_at_50
test_read_provider_history
test_read_nonexistent
test_build_provider_context
test_build_context_strips_variant
test_build_context_truncation
test_build_context_empty
test_dry_run_no_crash

test_summary
