#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "retired OpenClaw integration"

retired_token_pattern='openclaw|octo-claw|OCTO_CLAW|CLAUDE_OCTOPUS_OPENCLAW'

assert_absent() {
    local relative_path="$1"
    test_case "$relative_path does not ship"
    if [[ ! -e "$PROJECT_ROOT/$relative_path" ]]; then
        test_pass
    else
        test_fail "$relative_path must be removed"
    fi
}

for relative_path in \
    openclaw \
    scripts/build-openclaw.sh \
    tests/validate-openclaw.sh \
    tests/unit/test-openclaw-compat.sh \
    tests/unit/test-openclaw-integration.sh; do
    assert_absent "$relative_path"
done

test_case "active product files contain no OpenClaw integration wiring"
matches="$(
    cd "$PROJECT_ROOT"
    git grep -n -i -E "$retired_token_pattern" -- \
        ':!CHANGELOG.md' \
        ':!docs/plans/**' \
        ':!docs/superpowers/**' \
        ':!docs/UPGRADING-V11.0.1.md' \
        ':!README.md' \
        ':!.claude-plugin/plugin.json' \
        ':!.claude-plugin/marketplace.json' \
        ':!tests/unit/test-retired-openclaw.sh' \
        ':!tests/unit/test-retired-claw-admin.sh' \
        || true
)"
if [[ -z "$matches" ]]; then
    test_pass
else
    test_fail "retired OpenClaw wiring remains:\n$matches"
fi

test_case "the retirement release records removal without current metadata wiring"
expected_removal_note="Remove the unused OpenClaw integration and simplify MCP setup"
retirement_release="11.0.1"
retirement_heading="## [${retirement_release}]"
retirement_note_matches="$({
    cd "$PROJECT_ROOT"
    git grep -n -F -- "$retirement_heading" CHANGELOG.md || true
    git grep -n -F -- "$expected_removal_note" CHANGELOG.md || true
})"
current_metadata_matches="$({
    cd "$PROJECT_ROOT"
    git grep -n -i -E "$retired_token_pattern" -- \
        README.md \
        .claude-plugin/plugin.json \
        .claude-plugin/marketplace.json \
        || true
})"
if printf '%s\n' "$retirement_note_matches" | grep -qF "$retirement_heading" &&
   printf '%s\n' "$retirement_note_matches" | grep -qF "$expected_removal_note" &&
   [[ -z "$current_metadata_matches" ]]; then
    test_pass
else
    test_fail "retirement release note or current metadata contract is invalid:\n${retirement_note_matches:-missing $retirement_heading or removal note}\n${current_metadata_matches:-}"
fi

test_case "retirement release version matching rejects longer version prefixes"
escaped_retirement_release="${retirement_release//./\\.}"
retirement_release_pattern="v${escaped_retirement_release}([^0-9.]|$)"
if ! [[ "v${retirement_release}0" =~ $retirement_release_pattern ]] &&
   ! [[ "v${retirement_release}.1" =~ $retirement_release_pattern ]]; then
    test_pass
else
    test_fail "release version matching accepted a longer version prefix"
fi

test_case "MCP server starts without the retired OpenClaw opt-in variable"
if ! grep -q 'OCTO_CLAW_ENABLED' "$PROJECT_ROOT/mcp-server/src/index.ts"; then
    test_pass
else
    test_fail "mcp-server/src/index.ts still depends on OCTO_CLAW_ENABLED"
fi

test_summary
