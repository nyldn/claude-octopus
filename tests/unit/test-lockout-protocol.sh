#!/bin/bash
# tests/unit/test-lockout-protocol.sh
# Tests the reviewer lockout protocol (v8.18.0)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Reviewer Lockout Protocol"

# Source orchestrate.sh functions in a subshell-safe way
setup_lockout_env() {
    # Initialize variables that orchestrate.sh needs
    LOCKED_PROVIDERS=""
    LOG_LEVEL="${LOG_LEVEL:-WARN}"

    # Minimal log function for testing
    log() { :; }
}

# Define the functions inline for unit testing (avoids sourcing entire orchestrate.sh)
lock_provider() {
    local provider="$1"
    if ! echo "$LOCKED_PROVIDERS" | grep -qw "$provider"; then
        LOCKED_PROVIDERS="${LOCKED_PROVIDERS:+$LOCKED_PROVIDERS }$provider"
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

reset_provider_lockouts() {
    LOCKED_PROVIDERS=""
}

# ── Tests ──

test_lock_provider() {
    test_case "lock_provider adds provider to locked list"
    setup_lockout_env

    lock_provider "codex"

    if [[ "$LOCKED_PROVIDERS" == "codex" ]]; then
        test_pass
    else
        test_fail "Expected 'codex', got '$LOCKED_PROVIDERS'"
    fi
}

test_lock_multiple_providers() {
    test_case "lock_provider handles multiple providers"
    setup_lockout_env

    lock_provider "codex"
    lock_provider "gemini"

    if echo "$LOCKED_PROVIDERS" | grep -qw "codex" && echo "$LOCKED_PROVIDERS" | grep -qw "gemini"; then
        test_pass
    else
        test_fail "Expected both codex and gemini locked, got '$LOCKED_PROVIDERS'"
    fi
}

test_lock_provider_idempotent() {
    test_case "lock_provider is idempotent (no duplicates)"
    setup_lockout_env

    lock_provider "codex"
    lock_provider "codex"

    local count
    count=$(echo "$LOCKED_PROVIDERS" | tr ' ' '\n' | grep -c "^codex$")

    if [[ "$count" -eq 1 ]]; then
        test_pass
    else
        test_fail "Expected 1 occurrence of codex, got $count"
    fi
}

test_is_provider_locked() {
    test_case "is_provider_locked returns correct status"
    setup_lockout_env

    lock_provider "codex"

    if is_provider_locked "codex" && ! is_provider_locked "gemini"; then
        test_pass
    else
        test_fail "Lock check failed"
    fi
}

test_alternate_codex_to_gemini() {
    test_case "get_alternate_provider routes codex to gemini"
    setup_lockout_env

    local alt
    alt=$(get_alternate_provider "codex")

    if [[ "$alt" == "gemini" ]]; then
        test_pass
    else
        test_fail "Expected 'gemini', got '$alt'"
    fi
}

test_alternate_gemini_to_codex() {
    test_case "get_alternate_provider routes gemini to codex"
    setup_lockout_env

    local alt
    alt=$(get_alternate_provider "gemini")

    if [[ "$alt" == "codex" ]]; then
        test_pass
    else
        test_fail "Expected 'codex', got '$alt'"
    fi
}

test_alternate_cascade() {
    test_case "get_alternate_provider cascades when first alternate locked"
    setup_lockout_env

    lock_provider "gemini"
    local alt
    alt=$(get_alternate_provider "codex")

    if [[ "$alt" == "claude-sonnet" ]]; then
        test_pass
    else
        test_fail "Expected 'claude-sonnet', got '$alt'"
    fi
}

test_alternate_all_locked() {
    test_case "get_alternate_provider returns original when all locked"
    setup_lockout_env

    lock_provider "gemini"
    lock_provider "claude-sonnet"
    local alt
    alt=$(get_alternate_provider "codex")

    if [[ "$alt" == "codex" ]]; then
        test_pass
    else
        test_fail "Expected 'codex' (fallback), got '$alt'"
    fi
}

test_reset_lockouts() {
    test_case "reset_provider_lockouts clears all locks"
    setup_lockout_env

    lock_provider "codex"
    lock_provider "gemini"
    reset_provider_lockouts

    if [[ -z "$LOCKED_PROVIDERS" ]]; then
        test_pass
    else
        test_fail "Expected empty, got '$LOCKED_PROVIDERS'"
    fi
}

test_codex_variants() {
    test_case "get_alternate_provider handles codex variants (codex-fast, codex-mini)"
    setup_lockout_env

    local alt_fast alt_mini
    alt_fast=$(get_alternate_provider "codex-fast")
    alt_mini=$(get_alternate_provider "codex-mini")

    if [[ "$alt_fast" == "gemini" && "$alt_mini" == "gemini" ]]; then
        test_pass
    else
        test_fail "Expected gemini for both, got fast='$alt_fast' mini='$alt_mini'"
    fi
}

test_gemini_variants() {
    test_case "get_alternate_provider handles gemini-fast variant"
    setup_lockout_env

    local alt
    alt=$(get_alternate_provider "gemini-fast")

    if [[ "$alt" == "codex" ]]; then
        test_pass
    else
        test_fail "Expected 'codex', got '$alt'"
    fi
}

test_dry_run_includes_sentinel() {
    test_case "Dry-run probe still works with lockout code present"

    local output
    output=$("$PROJECT_ROOT/scripts/orchestrate.sh" -n probe "test" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        test_pass
    else
        test_fail "Dry-run failed with exit code $exit_code"
    fi
}

# Run all tests
test_lock_provider
test_lock_multiple_providers
test_lock_provider_idempotent
test_is_provider_locked
test_alternate_codex_to_gemini
test_alternate_gemini_to_codex
test_alternate_cascade
test_alternate_all_locked
test_reset_lockouts
test_codex_variants
test_gemini_variants
test_dry_run_includes_sentinel

test_summary
