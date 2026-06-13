#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Provider contract audit"

AUDIT="$PROJECT_ROOT/scripts/helpers/audit-provider-contracts.sh"

test_audit_script_syntax() {
    test_case "audit-provider-contracts.sh has valid syntax"
    if bash -n "$AUDIT"; then test_pass
    else test_fail "syntax check failed"; fi
}

test_audit_passes_current_tree() {
    test_case "provider contract audit passes current tree"
    local output
    if output="$(bash "$AUDIT" 2>&1)"; then
        if printf '%s\n' "$output" | grep -q 'SUMMARY .*fail=0'; then test_pass
        else test_fail "missing fail=0 summary: $output"; fi
    else
        test_fail "$output"
    fi
}

test_audit_guards_qwen_free_tier_guidance() {
    test_case "audit guards against stale qwen free-tier setup guidance"
    if grep -q 'Qwen:.*free tier' "$AUDIT"; then test_pass
    else test_fail "audit does not check stale qwen guidance"; fi
}

test_audit_guards_event_stream_contract() {
    test_case "audit guards provider.status event hook"
    if grep -q 'provider\\.status' "$AUDIT"; then test_pass
    else test_fail "audit does not check provider.status hook"; fi
}

test_audit_script_syntax
test_audit_passes_current_tree
test_audit_guards_qwen_free_tier_guidance
test_audit_guards_event_stream_contract

test_summary
