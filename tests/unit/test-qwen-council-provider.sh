#!/bin/bash
# tests/unit/test-qwen-council-provider.sh
# Tests that Qwen is a seatable council provider org:
#   - present in the council auto/allowed provider lists
#   - representable by a persona so council diversity/scoring can seat it
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Qwen council provider"

COUNCIL="$PROJECT_ROOT/scripts/lib/council.sh"
CONFIG="$PROJECT_ROOT/agents/config.yaml"
USAGE="$PROJECT_ROOT/scripts/lib/usage-help.sh"

test_qwen_in_auto_list() {
    test_case "council auto provider list includes qwen"

    if grep -q 'claude,codex,gemini,qwen,opencode,openrouter' "$COUNCIL"; then
        test_pass
    else
        test_fail "council.sh auto provider list should include qwen"
    fi
}

test_qwen_no_stale_list() {
    test_case "no stale qwen-less provider list remains in council.sh"

    if grep -q 'claude,codex,gemini,opencode,openrouter' "$COUNCIL"; then
        test_fail "council.sh still contains a provider list without qwen"
    else
        test_pass
    fi
}

test_qwen_validates() {
    test_case "council_validate_provider_list accepts an explicit qwen request"

    # council.sh is source-safe (function definitions only); validate is pure.
    if ( source "$COUNCIL" && council_validate_provider_list "claude,codex,qwen" >/dev/null 2>&1 ); then
        test_pass
    else
        test_fail "--providers claude,codex,qwen should be accepted"
    fi
}

test_qwen_persona_seat() {
    test_case "config.yaml gives the qwen org a council persona with codex fallback"

    local block
    block="$(awk '/^  python-pro:/{f=1} f{print} f&&/^  [a-z].*:/&&!/^  python-pro:/{exit}' "$CONFIG")"
    if [[ "$block" == *"cli: qwen"* ]] && [[ "$block" == *"fallback_cli: codex"* ]]; then
        test_pass
    else
        test_fail "a persona should default to cli: qwen with fallback_cli: codex"
    fi
}

test_qwen_usage_doc() {
    test_case "usage help lists qwen as a --providers option"

    if grep -q 'claude,codex,gemini,qwen,opencode,openrouter' "$USAGE"; then
        test_pass
    else
        test_fail "usage-help.sh should document qwen in the --providers list"
    fi
}

test_qwen_syntax() {
    test_case "council.sh and usage-help.sh remain valid bash"

    if bash -n "$COUNCIL" && bash -n "$USAGE"; then
        test_pass
    else
        test_fail "edited scripts have syntax errors"
    fi
}

test_qwen_in_auto_list
test_qwen_no_stale_list
test_qwen_validates
test_qwen_persona_seat
test_qwen_usage_doc
test_qwen_syntax

test_summary
