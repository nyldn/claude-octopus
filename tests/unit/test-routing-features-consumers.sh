#!/usr/bin/env bash
# Static regression checks for routing.features.* consumers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROUTING="$PROJECT_ROOT/scripts/lib/routing.sh"
PARALLEL="$PROJECT_ROOT/scripts/lib/parallel.sh"
DEBATE="$PROJECT_ROOT/scripts/lib/debate.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "routing.features consumers"

assert_file_has() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    test_case "$label"
    if grep -qE "$pattern" "$file"; then
        test_pass
    else
        test_fail "pattern not found in $(basename "$file"): $pattern"
    fi
}

assert_file_lacks() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    test_case "$label"
    if grep -qE "$pattern" "$file"; then
        test_fail "unexpected pattern found in $(basename "$file"): $pattern"
    else
        test_pass
    fi
}

for file in "$ROUTING" "$PARALLEL" "$DEBATE"; do
    test_case "$(basename "$file") has valid bash syntax"
    if bash -n "$file" 2>/dev/null; then
        test_pass
    else
        test_fail "syntax error in $file"
    fi
done

assert_file_has "$ROUTING" '^resolve_provider_to_agent\(\)' \
    "shared provider resolver exists"

assert_file_has "$PARALLEL" 'resolve_provider_to_agent "\$_a"' \
    "fan_out uses shared provider resolver"

assert_file_has "$DEBATE" 'resolve_provider_to_agent "\$_provider"' \
    "debate uses shared provider resolver"

assert_file_has "$DEBATE" 'grep -cv .*\|\| true' \
    "debate participant count is pipefail-safe"

assert_file_has "$DEBATE" '2>/dev/null \|\| true' \
    "debate config jq read is failure-tolerant"

assert_file_has "$PARALLEL" '2>/dev/null \|\| true' \
    "parallel config jq read is failure-tolerant"

assert_file_has "$DEBATE" '_resolved_count' \
    "debate config logging is gated on resolved participants"

assert_file_lacks "$DEBATE" 'codex, gemini, sonnet, or hybrid' \
    "debate synthesis choices are not hardcoded"

assert_file_has "$DEBATE" '\$\{label_a_upper\}, \$\{label_b_upper\}, \$\{label_c_upper\}, or hybrid' \
    "debate synthesis choices use dynamic labels"

test_case "provider resolver maps configured tokens to available agents"
AVAILABLE_AGENTS="codex gemini claude-sonnet claude-opus openrouter qwen perplexity"
source "$ROUTING"
if [[ "$(resolve_provider_to_agent claude)" == "claude-sonnet" ]] \
   && [[ "$(resolve_provider_to_agent openrouter)" == "openrouter" ]] \
   && ! resolve_provider_to_agent missing-provider >/dev/null 2>&1; then
    test_pass
else
    test_fail "provider resolver did not map/validate expected tokens"
fi

test_summary
