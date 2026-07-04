#!/bin/bash
# tests/unit/test-agy-council-provider.sh
# Tests that agy is a seatable council provider org:
#   - present in the council auto/allowed provider lists
#   - cli_to_provider maps agy variants correctly
#   - usage help documents it
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Agy council provider"

COUNCIL="$PROJECT_ROOT/scripts/lib/council.sh"
USAGE="$PROJECT_ROOT/scripts/lib/usage-help.sh"

test_agy_in_auto_list() {
    test_case "council auto provider list includes agy"

    if grep -q 'gemini,agy,qwen,opencode' "$COUNCIL"; then
        test_pass
    else
        test_fail "council.sh auto provider list should include agy"
    fi
}

test_agy_no_stale_list() {
    test_case "no stale agy-less provider list remains in council.sh"

    if grep -q 'claude,codex,gemini,qwen,opencode,openrouter' "$COUNCIL"; then
        test_fail "council.sh still contains a provider list without agy"
    else
        test_pass
    fi
}

test_agy_validates() {
    test_case "council_validate_provider_list accepts an explicit agy request"

    if ( source "$COUNCIL" && council_validate_provider_list "claude,codex,agy" >/dev/null 2>&1 ); then
        test_pass
    else
        test_fail "--providers claude,codex,agy should be accepted"
    fi
}

test_agy_cli_to_provider() {
    test_case "council_cli_to_provider maps agy variants to agy"

    local result
    result="$( source "$COUNCIL" && council_cli_to_provider "agy-turbo" )"
    if [[ "$result" == "agy" ]]; then
        test_pass
    else
        test_fail "council_cli_to_provider 'agy-turbo' returned '$result', expected 'agy'"
    fi
}

test_agy_usage_doc() {
    test_case "usage help lists agy as a --providers option"

    if grep -q 'gemini,agy,qwen,opencode' "$USAGE"; then
        test_pass
    else
        test_fail "usage-help.sh should document agy in the --providers list"
    fi
}

test_agy_syntax() {
    test_case "council.sh and usage-help.sh remain valid bash"

    if bash -n "$COUNCIL" && bash -n "$USAGE"; then
        test_pass
    else
        test_fail "edited scripts have syntax errors"
    fi
}

test_agy_in_auto_list
test_agy_no_stale_list
test_agy_validates
test_agy_cli_to_provider
test_agy_usage_doc
test_agy_syntax

test_summary
