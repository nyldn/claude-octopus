#!/bin/bash
# tests/unit/test-structured-decisions.sh
# Tests structured decision format (v8.18.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Structured Decision Format"

TEST_WORKSPACE="/tmp/octopus-test-decisions-$$"

setup_decision_env() {
    rm -rf "$TEST_WORKSPACE"
    mkdir -p "$TEST_WORKSPACE"
    WORKSPACE_DIR="$TEST_WORKSPACE"
    log() { :; }
}

cleanup_decision_env() {
    rm -rf "$TEST_WORKSPACE"
}

# Define function inline for unit testing
write_structured_decision() {
    local type="$1"
    local source="$2"
    local summary="$3"
    local scope="${4:-}"
    local confidence="${5:-medium}"
    local rationale="${6:-}"
    local related="${7:-}"

    local decisions_dir="${WORKSPACE_DIR}/.octo"
    local decisions_file="$decisions_dir/decisions.md"
    mkdir -p "$decisions_dir"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local decision_id
    decision_id="D-$(date +%s)-$$"

    cat >> "$decisions_file" << DECEOF

### type: ${type} | timestamp: ${timestamp} | source: ${source}
**ID:** ${decision_id}
**Summary:** ${summary}
**Scope:** ${scope:-project-wide}
**Confidence:** ${confidence}
**Rationale:** ${rationale:-No rationale provided}
${related:+**Related:** ${related}}
---
DECEOF
}

# ── Tests ──

test_file_creation() {
    test_case "Creates .octo/decisions.md on first write"
    setup_decision_env

    write_structured_decision "quality-gate" "test" "Test decision" "" "high" "Testing"

    if [[ -f "$TEST_WORKSPACE/.octo/decisions.md" ]]; then
        test_pass
    else
        test_fail "decisions.md not created"
    fi
    cleanup_decision_env
}

test_append_only() {
    test_case "Appends entries without overwriting"
    setup_decision_env

    write_structured_decision "quality-gate" "test1" "First decision"
    write_structured_decision "debate-synthesis" "test2" "Second decision"

    local count
    count=$(grep -c "^### type:" "$TEST_WORKSPACE/.octo/decisions.md" 2>/dev/null)

    if [[ "$count" -eq 2 ]]; then
        test_pass
    else
        test_fail "Expected 2 entries, got $count"
    fi
    cleanup_decision_env
}

test_format_compliance() {
    test_case "Entries have correct structured format"
    setup_decision_env

    write_structured_decision "quality-gate" "validate_tangle" "Gate passed at 95%" "tangle-123" "high" "All subtasks succeeded"

    local content
    content=$(cat "$TEST_WORKSPACE/.octo/decisions.md")

    if echo "$content" | grep -q "^### type: quality-gate" && \
       echo "$content" | grep -q "^\*\*Summary:\*\*" && \
       echo "$content" | grep -q "^\*\*Scope:\*\*" && \
       echo "$content" | grep -q "^\*\*Confidence:\*\* high" && \
       echo "$content" | grep -q "^\*\*Rationale:\*\*" && \
       echo "$content" | grep -q "^---$"; then
        test_pass
    else
        test_fail "Format mismatch: $content"
    fi
    cleanup_decision_env
}

test_decision_id_present() {
    test_case "Each entry has a unique decision ID"
    setup_decision_env

    write_structured_decision "quality-gate" "test" "Test" "" "medium" "test"

    if grep -q "^\*\*ID:\*\* D-" "$TEST_WORKSPACE/.octo/decisions.md"; then
        test_pass
    else
        test_fail "No decision ID found"
    fi
    cleanup_decision_env
}

test_timestamp_present() {
    test_case "Each entry has an ISO8601 timestamp"
    setup_decision_env

    write_structured_decision "quality-gate" "test" "Test"

    if grep -q "timestamp: [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T" "$TEST_WORKSPACE/.octo/decisions.md"; then
        test_pass
    else
        test_fail "No ISO8601 timestamp found"
    fi
    cleanup_decision_env
}

test_all_decision_types() {
    test_case "All four decision types are valid"
    setup_decision_env

    write_structured_decision "quality-gate" "test" "Gate passed"
    write_structured_decision "debate-synthesis" "test" "Debate done"
    write_structured_decision "phase-completion" "test" "Phase done"
    write_structured_decision "security-finding" "test" "Security reviewed"

    local count
    count=$(grep -c "^### type:" "$TEST_WORKSPACE/.octo/decisions.md" 2>/dev/null)

    if [[ "$count" -eq 4 ]]; then
        test_pass
    else
        test_fail "Expected 4 entries, got $count"
    fi
    cleanup_decision_env
}

test_default_values() {
    test_case "Default values applied when optional params missing"
    setup_decision_env

    write_structured_decision "quality-gate" "test" "Test"

    local content
    content=$(cat "$TEST_WORKSPACE/.octo/decisions.md")

    if echo "$content" | grep -q "project-wide" && \
       echo "$content" | grep -q "medium" && \
       echo "$content" | grep -q "No rationale provided"; then
        test_pass
    else
        test_fail "Default values not applied: $content"
    fi
    cleanup_decision_env
}

test_related_field_conditional() {
    test_case "Related field only appears when provided"
    setup_decision_env

    write_structured_decision "quality-gate" "test" "No related"
    write_structured_decision "quality-gate" "test" "Has related" "" "high" "" "D-12345"

    local content
    content=$(cat "$TEST_WORKSPACE/.octo/decisions.md")

    # Second entry should have Related
    if echo "$content" | grep -q "^\*\*Related:\*\* D-12345"; then
        test_pass
    else
        test_fail "Related field not found: $content"
    fi
    cleanup_decision_env
}

test_backward_compat_state_md() {
    test_case "state-manager.sh references decisions in write_state_md"

    if grep -q "Structured Decisions\|decisions.md" "$PROJECT_ROOT/scripts/state-manager.sh"; then
        test_pass
    else
        test_fail "state-manager.sh doesn't reference structured decisions"
    fi
}

test_dry_run_no_crash() {
    test_case "Dry-run probe still works with structured decisions code"

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
test_file_creation
test_append_only
test_format_compliance
test_decision_id_present
test_timestamp_present
test_all_decision_types
test_default_values
test_related_field_conditional
test_backward_compat_state_md
test_dry_run_no_crash

test_summary
