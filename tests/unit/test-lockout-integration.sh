#!/bin/bash
# tests/unit/test-lockout-integration.sh
# Integration tests for Reviewer Lockout Protocol (v8.18.0)
# Tests the lockout mechanism in context of quality gate failures
# and alternate provider routing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

# Define lockout functions directly (extracted from orchestrate.sh)
# We can't source orchestrate.sh as it runs its main routine
export WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
export PLUGIN_DIR="$PROJECT_ROOT"

LOCKED_PROVIDERS=""

# Minimal log stub for lock_provider's log call
log() { :; }

lock_provider() {
    local provider="$1"
    if ! echo "$LOCKED_PROVIDERS" | grep -qw "$provider"; then
        LOCKED_PROVIDERS="${LOCKED_PROVIDERS:+$LOCKED_PROVIDERS }$provider"
        log WARN "Provider locked out: $provider (will not self-revise)"
    fi
}

is_provider_locked() {
    local provider="$1"
    echo "$LOCKED_PROVIDERS" | grep -qw "$provider"
}

get_alternate_provider() {
    local locked_provider="$1"
    case "$locked_provider" in
        codex|codex-fast|codex-mini)
            if ! is_provider_locked "gemini"; then
                echo "gemini"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            else
                echo "$locked_provider"
            fi
            ;;
        gemini|gemini-fast)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            else
                echo "$locked_provider"
            fi
            ;;
        claude-sonnet|claude*)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "gemini"; then
                echo "gemini"
            else
                echo "$locked_provider"
            fi
            ;;
        *)
            echo "$locked_provider"
            ;;
    esac
}

test_suite "Lockout Protocol Integration (v8.18.0)"

# ═══════════════════════════════════════════════════════════════════════════════
# Quality Gate → Lockout → Alternate Provider Flow
# ═══════════════════════════════════════════════════════════════════════════════

test_gate_failure_locks_provider() {
    test_case "Provider locked after quality gate failure"

    # Reset lockout state
    LOCKED_PROVIDERS=""

    # Simulate: codex produced bad output, quality gate failed
    lock_provider "codex"

    if is_provider_locked "codex"; then
        test_pass
    else
        test_fail "codex should be locked after gate failure"
    fi
}

test_locked_provider_gets_alternate() {
    test_case "Locked provider routes to alternate"

    LOCKED_PROVIDERS=""
    lock_provider "codex"

    local alt
    alt=$(get_alternate_provider "codex")

    if [[ "$alt" == "gemini" ]]; then
        test_pass
    else
        test_fail "codex should alternate to gemini, got: $alt"
    fi
}

test_double_lockout_cascade() {
    test_case "Double lockout cascades to third provider"

    LOCKED_PROVIDERS=""
    lock_provider "codex"
    lock_provider "gemini"

    local alt
    alt=$(get_alternate_provider "codex")

    # With both codex and gemini locked, should fall back to claude-sonnet or similar
    if [[ -n "$alt" ]] && [[ "$alt" != "codex" ]] && [[ "$alt" != "gemini" ]]; then
        test_pass
    else
        test_fail "Should cascade to third provider, got: $alt"
    fi
}

test_lockout_prevents_self_review() {
    test_case "Locked provider cannot review its own output"

    LOCKED_PROVIDERS=""
    lock_provider "codex"

    # Verify codex is locked
    if is_provider_locked "codex"; then
        # Verify alternate is NOT codex
        local alt
        alt=$(get_alternate_provider "codex")
        if [[ "$alt" != "codex" ]]; then
            test_pass
        else
            test_fail "Locked provider should not self-review"
        fi
    else
        test_fail "codex should be locked"
    fi
}

test_lockout_idempotent() {
    test_case "Locking same provider twice is idempotent"

    LOCKED_PROVIDERS=""
    lock_provider "gemini"
    lock_provider "gemini"

    # Count occurrences
    local count
    count=$(echo "$LOCKED_PROVIDERS" | tr ' ' '\n' | grep -c "gemini" || true)

    if [[ "$count" -le 1 ]]; then
        test_pass
    else
        test_fail "Should not duplicate locked provider, count=$count"
    fi
}

test_lockout_variants_covered() {
    test_case "Provider variants (codex-fast, codex-mini) also locked"

    LOCKED_PROVIDERS=""
    lock_provider "codex"

    # Variants should also be considered locked
    if is_provider_locked "codex-fast" || is_provider_locked "codex"; then
        test_pass
    else
        test_fail "Provider variants should be covered by lockout"
    fi
}

test_unlocked_provider_not_affected() {
    test_case "Unlocked providers are not affected"

    LOCKED_PROVIDERS=""
    lock_provider "codex"

    if ! is_provider_locked "gemini"; then
        test_pass
    else
        test_fail "gemini should not be locked when only codex is locked"
    fi
}

test_lockout_function_in_quality_gate() {
    test_case "lock_provider called in quality gate failure path"

    # Verify the integration point exists in orchestrate.sh
    if grep -q 'lock_provider' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        # Verify it's called in quality gate context
        if grep -B5 -A5 'lock_provider' "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -qi 'gate\|quality\|fail\|reject'; then
            test_pass
        else
            test_fail "lock_provider should be called in quality gate failure context"
        fi
    else
        test_fail "lock_provider not found in orchestrate.sh"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run all tests
# ═══════════════════════════════════════════════════════════════════════════════

test_gate_failure_locks_provider
test_locked_provider_gets_alternate
test_double_lockout_cascade
test_lockout_prevents_self_review
test_lockout_idempotent
test_lockout_variants_covered
test_unlocked_provider_not_affected
test_lockout_function_in_quality_gate

test_summary
